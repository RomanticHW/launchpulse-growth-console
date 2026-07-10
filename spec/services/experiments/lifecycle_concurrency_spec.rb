require "rails_helper"
require "timeout"

RSpec.describe Experiments::LifecycleService, "lifecycle concurrency" do
  self.use_transactional_tests = false

  def wait_for_database_lock(pid)
    Timeout.timeout(5) do
      loop do
        activity = ActiveRecord::Base.connection.select_one(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT wait_event_type, query FROM pg_stat_activity WHERE pid = ?",
            pid
          ])
        )
        break activity.fetch("query") if activity&.fetch("wait_event_type") == "Lock"

        Thread.pass
      end
    end
  end

  def expect_transition_then_complete_to_serialize(initial_status:, transition:, audit_action:)
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, status: initial_status)
    transition_ready = Queue.new
    transition_release = Queue.new
    transition_results = Queue.new
    complete_started = Queue.new
    complete_results = Queue.new
    transition_thread = nil
    complete_thread = nil
    gated_lifecycle_class = Class.new(described_class) do
      define_method(:initialize) do |ready:, release:, gated_action:|
        @ready = ready
        @release = release
        @gated_action = gated_action
      end

      define_method(:audit!) do |**kwargs|
        if kwargs.fetch(:action) == @gated_action
          @ready << true
          @release.pop
        end
        super(**kwargs)
      end

      private :audit!
    end

    begin
      transition_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            current_experiment = Experiment.find(experiment.id)
            gated_lifecycle_class.new(
              ready: transition_ready,
              release: transition_release,
              gated_action: audit_action
            ).public_send(transition, experiment: current_experiment, user: nil, account: current_experiment.site.account)
            transition_results << [ :ok, backend_pid ]
          rescue StandardError => error
            transition_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { transition_ready.pop }

      complete_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          complete_started << backend_pid
          begin
            current_experiment = Experiment.find(experiment.id)
            described_class.new.complete!(
              experiment: current_experiment,
              user: nil,
              account: current_experiment.site.account
            )
            complete_results << [ :ok, backend_pid ]
          rescue StandardError => error
            complete_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      complete_backend_pid = Timeout.timeout(5) { complete_started.pop }
      blocked_query = wait_for_database_lock(complete_backend_pid)
      transition_release << true

      transition_result = Timeout.timeout(8) { transition_results.pop }
      complete_result = Timeout.timeout(8) { complete_results.pop }
      Timeout.timeout(5) do
        transition_thread.join
        complete_thread.join
      end

      expect(transition_result.last).not_to eq(complete_result.last)
      expect([ transition_result, complete_result ].filter_map { |result| result.second if result.first == :error })
        .not_to include(ActiveRecord::Deadlocked)
      expect(blocked_query).to include('FROM "sites"', "FOR UPDATE")
      expect(transition_result.first).to eq(:ok)
      expect(complete_result.first).to eq(:ok)
      expect(experiment.reload.status).to eq("completed")
    ensure
      transition_release << true if transition_thread&.alive?
      stuck_threads = []
      [ transition_thread, complete_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        stuck_threads << thread unless thread.join(1)
      end
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_threads.any?
    end
  end

  def expect_assignment_and_apply_winner_to_serialize(order:)
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, status: "completed", ended_at: Time.current)
    historical_variant = create(:variant, experiment:, key: "control", role: "control")
    winner = create(:variant, experiment:, key: "winner", role: "variant", props: section.props.merge("headline" => "Winner"))
    experiment.assignments.create!(visitor_id: "historical-visitor", variant: historical_variant)
    assignment_started = Queue.new
    assignment_ready = Queue.new
    assignment_release = Queue.new
    assignment_results = Queue.new
    lifecycle_started = Queue.new
    lifecycle_ready = Queue.new
    lifecycle_release = Queue.new
    lifecycle_results = Queue.new
    assignment_thread = nil
    lifecycle_thread = nil
    gated_lifecycle_class = Class.new(described_class) do
      define_method(:initialize) do |ready:, release:|
        @ready = ready
        @release = release
      end

      define_method(:audit!) do |**kwargs|
        if kwargs.fetch(:action) == "experiment_winner_applied"
          @ready << true
          @release.pop
        end
        super(**kwargs)
      end

      private :audit!
    end
    start_assignment = lambda do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          assignment_started << backend_pid
          begin
            assignment_id = nil
            event_id = nil
            ActiveRecord::Base.transaction do
              current_experiment = Experiment.find(experiment.id)
              assignment = Experiments::AssignmentService.new(current_experiment).assign("winner-race-visitor")
              assignment_id = assignment&.id
              if order == :assignment_first
                assignment_ready << true
                assignment_release.pop
              end
              event_id = Event.create!(
                site: Site.find(site.id),
                page: Page.find(page.id),
                event_type: "page_view",
                visitor_id: "winner-race-visitor",
                source: "direct",
                device: "desktop",
                occurred_at: Time.current,
                metadata: {}
              ).id
            end
            assignment_results << [ :ok, assignment_id, event_id, backend_pid ]
          rescue StandardError => error
            assignment_results << [ :error, error.class, backend_pid ]
          end
        end
      end
    end
    start_lifecycle = lambda do |gated|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          lifecycle_started << backend_pid
          begin
            current_experiment = Experiment.find(experiment.id)
            current_winner = current_experiment.variants.find(winner.id)
            service = gated ? gated_lifecycle_class.new(ready: lifecycle_ready, release: lifecycle_release) : described_class.new
            service.apply_winner!(
              experiment: current_experiment,
              variant: current_winner,
              user: nil,
              account: current_experiment.site.account
            )
            lifecycle_results << [ :ok, backend_pid ]
          rescue StandardError => error
            lifecycle_results << [ :error, error.class, backend_pid ]
          end
        end
      end
    end

    begin
      if order == :lifecycle_first
        lifecycle_thread = start_lifecycle.call(true)
        lifecycle_backend_pid = Timeout.timeout(5) { lifecycle_started.pop }
        Timeout.timeout(5) { lifecycle_ready.pop }
        assignment_thread = start_assignment.call
        assignment_backend_pid = Timeout.timeout(5) { assignment_started.pop }
        blocked_query = wait_for_database_lock(assignment_backend_pid)
        lifecycle_release << true
        expected_lock = "FOR KEY SHARE"
      else
        assignment_thread = start_assignment.call
        assignment_backend_pid = Timeout.timeout(5) { assignment_started.pop }
        Timeout.timeout(5) { assignment_ready.pop }
        lifecycle_thread = start_lifecycle.call(false)
        lifecycle_backend_pid = Timeout.timeout(5) { lifecycle_started.pop }
        blocked_query = wait_for_database_lock(lifecycle_backend_pid)
        assignment_release << true
        expected_lock = "FOR UPDATE"
      end

      assignment_result = Timeout.timeout(8) { assignment_results.pop }
      lifecycle_result = Timeout.timeout(8) { lifecycle_results.pop }
      Timeout.timeout(5) do
        assignment_thread.join
        lifecycle_thread.join
      end

      expect(assignment_backend_pid).not_to eq(lifecycle_backend_pid)
      expect([ assignment_result, lifecycle_result ].filter_map { |result| result.second if result.first == :error })
        .not_to include(ActiveRecord::Deadlocked)
      expect(blocked_query).to include('FROM "sites"', expected_lock)
      expect(assignment_result.first).to eq(:ok)
      expect(assignment_result.second).to be_nil
      expect(lifecycle_result.first).to eq(:ok)
      event = Event.find(assignment_result.third)
      expect(event).to have_attributes(experiment_id: nil, variant_id: nil, visitor_id: "winner-race-visitor")
      expect(experiment.reload).to have_attributes(winner_variant_id: winner.id)
      expect(experiment.winner_applied_at).to be_present
      expect(experiment.assignments.where(visitor_id: "winner-race-visitor")).to be_empty
      expect(experiment.assignments.count).to eq(1)
    ensure
      assignment_release << true if assignment_thread&.alive?
      lifecycle_release << true if lifecycle_thread&.alive?
      stuck_threads = []
      [ assignment_thread, lifecycle_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        stuck_threads << thread unless thread.join(1)
      end
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_threads.any?
    end
  end

  it "serializes launch and dismiss across separate database connections" do
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8,
      suggested_patch: { "cta" => "Get plan" }
    )
    patch = recommendation.create_section_patch!(
      section:,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    launch_ready = Queue.new
    launch_release = Queue.new
    launch_results = Queue.new
    dismiss_started = Queue.new
    dismiss_results = Queue.new
    launch_thread = nil
    dismiss_thread = nil
    gated_service_class = Class.new(described_class) do
      define_method(:initialize) do |ready:, release:|
        @ready = ready
        @release = release
      end

      define_method(:validate_launchable!) do |current_recommendation|
        @ready << true
        @release.pop
        super(current_recommendation)
      end

      private :validate_launchable!
    end

    begin
      launch_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            current_site = Site.find(site.id)
            experiment = gated_service_class.new(ready: launch_ready, release: launch_release).launch_from_recommendation!(
              site: current_site,
              recommendation: Recommendation.find(recommendation.id),
              user: nil,
              account: current_site.account
            )
            launch_results << [ :ok, experiment.id, backend_pid ]
          rescue StandardError => error
            launch_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { launch_ready.pop }

      dismiss_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          dismiss_started << true
          begin
            SectionPatch.find(patch.id).dismiss!
            dismiss_results << [ :ok, backend_pid ]
          rescue StandardError => error
            dismiss_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { dismiss_started.pop }

      dismiss_result = begin
        Timeout.timeout(0.5) { dismiss_results.pop }
      rescue Timeout::Error
        nil
      end
      launch_release << true

      launch_result = Timeout.timeout(5) { launch_results.pop }
      dismiss_result ||= Timeout.timeout(5) { dismiss_results.pop }
      Timeout.timeout(5) do
        launch_thread.join
        dismiss_thread.join
      end

      expect(launch_result.last).not_to eq(dismiss_result.last)
      expect(launch_result.first).to eq(:ok)
      expect(dismiss_result.first(2)).to eq([ :error, ActiveRecord::RecordInvalid ])
      expect([ recommendation.reload.status, patch.reload.status, site.experiments.active.count ])
        .to eq([ "testing", "testing", 1 ])
    ensure
      launch_release << true if launch_thread&.alive?
      stuck_threads = []
      [ launch_thread, dismiss_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        stuck_threads << thread unless thread.join(1)
      end
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_threads.any?
    end
  end

  it "serializes pause! before complete! with the site lock first" do
    expect_transition_then_complete_to_serialize(
      initial_status: "active",
      transition: :pause!,
      audit_action: "experiment_paused"
    )
  end

  it "serializes resume! before complete! with the site lock first" do
    expect_transition_then_complete_to_serialize(
      initial_status: "paused",
      transition: :resume!,
      audit_action: "experiment_resumed"
    )
  end

  it "holds the site lock through an assignment-first event transaction before complete!" do
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant")
    assignment_ready = Queue.new
    assignment_release = Queue.new
    assign_results = Queue.new
    close_started = Queue.new
    close_results = Queue.new
    assign_thread = nil
    close_thread = nil

    begin
      assign_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            assignment_id = nil
            event_id = nil
            ActiveRecord::Base.transaction do
              current_experiment = Experiment.find(experiment.id)
              assignment = Experiments::AssignmentService.new(current_experiment).assign("visitor-assign-first")
              assignment_id = assignment.id
              assignment_ready << [ assignment_id, backend_pid ]
              assignment_release.pop
              event_id = Event.create!(
                site: Site.find(site.id),
                page: Page.find(page.id),
                experiment: current_experiment,
                variant: assignment.variant,
                variant_key: assignment.variant.key,
                event_type: "form_submit",
                visitor_id: "visitor-assign-first",
                source: "direct",
                device: "desktop",
                occurred_at: Time.current,
                metadata: {}
              ).id
            end
            assign_results << [ :ok, assignment_id, event_id, backend_pid ]
          rescue StandardError => error
            assign_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      assignment_id, assign_backend_pid = Timeout.timeout(5) { assignment_ready.pop }

      close_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          close_started << backend_pid
          begin
            current_experiment = Experiment.find(experiment.id)
            described_class.new.complete!(
              experiment: current_experiment,
              user: nil,
              account: current_experiment.site.account
            )
            close_results << [ :ok, backend_pid ]
          rescue StandardError => error
            close_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      close_backend_pid = Timeout.timeout(5) { close_started.pop }
      wait_for_database_lock(close_backend_pid)
      assignment_release << true

      assign_result = Timeout.timeout(8) { assign_results.pop }
      close_result = Timeout.timeout(8) { close_results.pop }
      Timeout.timeout(5) do
        assign_thread.join
        close_thread.join
      end

      expect(assign_backend_pid).not_to eq(close_backend_pid)
      expect([ assign_result, close_result ].filter_map { |result| result.second if result.first == :error })
        .not_to include(ActiveRecord::Deadlocked)
      expect(assign_result.first(3)).to eq([ :ok, assignment_id, Event.find_by!(visitor_id: "visitor-assign-first").id ])
      expect(close_result.first).to eq(:ok)
      expect(experiment.reload.status).to eq("completed")
      expect(experiment.assignments.where(visitor_id: "visitor-assign-first").count).to eq(1)
    ensure
      assignment_release << true if assign_thread&.alive?
      stuck_threads = []
      [ assign_thread, close_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        stuck_threads << thread unless thread.join(1)
      end
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_threads.any?
    end
  end

  it "waits for a lifecycle-first site lock and does not create an assignment or event" do
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant")
    close_ready = Queue.new
    close_release = Queue.new
    close_results = Queue.new
    assign_started = Queue.new
    assign_results = Queue.new
    close_thread = nil
    assign_thread = nil
    gated_lifecycle_class = Class.new(described_class) do
      define_method(:initialize) do |ready:, release:|
        @ready = ready
        @release = release
      end

      define_method(:audit!) do |**kwargs|
        if kwargs.fetch(:action) == "experiment_completed"
          @ready << true
          @release.pop
        end
        super(**kwargs)
      end

      private :audit!
    end

    begin
      close_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            current_experiment = Experiment.find(experiment.id)
            gated_lifecycle_class.new(ready: close_ready, release: close_release).complete!(
              experiment: current_experiment,
              user: nil,
              account: current_experiment.site.account
            )
            close_results << [ :ok, backend_pid ]
          rescue StandardError => error
            close_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { close_ready.pop }

      assign_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          assign_started << backend_pid
          begin
            assignment_id = nil
            event_id = nil
            ActiveRecord::Base.transaction do
              current_experiment = Experiment.find(experiment.id)
              assignment = Experiments::AssignmentService.new(current_experiment).assign("visitor-close-first")
              assignment_id = assignment&.id
              if assignment
                event_id = Event.create!(
                  site: Site.find(site.id),
                  page: Page.find(page.id),
                  experiment: current_experiment,
                  variant: assignment.variant,
                  variant_key: assignment.variant.key,
                  event_type: "form_submit",
                  visitor_id: "visitor-close-first",
                  source: "direct",
                  device: "desktop",
                  occurred_at: Time.current,
                  metadata: {}
                ).id
              end
            end
            assign_results << [ :ok, assignment_id, event_id, backend_pid ]
          rescue StandardError => error
            assign_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      assign_backend_pid = Timeout.timeout(5) { assign_started.pop }
      wait_for_database_lock(assign_backend_pid)
      close_release << true

      close_result = Timeout.timeout(8) { close_results.pop }
      assign_result = Timeout.timeout(8) { assign_results.pop }
      Timeout.timeout(5) do
        close_thread.join
        assign_thread.join
      end

      expect(close_result.last).not_to eq(assign_result.last)
      expect([ assign_result, close_result ].filter_map { |result| result.second if result.first == :error })
        .not_to include(ActiveRecord::Deadlocked)
      expect(close_result.first).to eq(:ok)
      expect(assign_result.first(3)).to eq([ :ok, nil, nil ])
      expect(experiment.reload.status).to eq("completed")
      expect(experiment.assignments.where(visitor_id: "visitor-close-first")).to be_empty
      expect(site.events.where(visitor_id: "visitor-close-first")).to be_empty
    ensure
      close_release << true if close_thread&.alive?
      stuck_threads = []
      [ close_thread, assign_thread ].compact.each do |thread|
        thread.kill if thread.alive?
        stuck_threads << thread unless thread.join(1)
      end
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_threads.any?
    end
  end

  it "waits on the site lock when apply_winner! starts before a completed-experiment assignment transaction" do
    expect_assignment_and_apply_winner_to_serialize(order: :lifecycle_first)
  end

  it "holds the site lock through an unattributed event before apply_winner!" do
    expect_assignment_and_apply_winner_to_serialize(order: :assignment_first)
  end

  it "does not assign from a stale active record after apply_winner! finishes on another connection" do
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "variant", props: section.props.merge("headline" => "Winner"))
    stale_experiment = Experiment.find(experiment.id)
    main_backend_pid = ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
    lifecycle_results = Queue.new
    lifecycle_thread = nil

    begin
      lifecycle_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            current_experiment = Experiment.find(experiment.id)
            current_variant = current_experiment.variants.find(variant.id)
            service = described_class.new
            service.complete!(experiment: current_experiment, user: nil, account: current_experiment.site.account)
            service.apply_winner!(experiment: current_experiment, variant: current_variant, user: nil, account: current_experiment.site.account)
            lifecycle_results << [ :ok, backend_pid ]
          rescue StandardError => error
            lifecycle_results << [ :error, error.class, backend_pid ]
          end
        end
      end

      lifecycle_result = Timeout.timeout(5) { lifecycle_results.pop }
      Timeout.timeout(5) { lifecycle_thread.join }
      assignment = Experiments::AssignmentService.new(stale_experiment).assign("visitor-after-winner")

      expect(lifecycle_result.first).to eq(:ok)
      expect(lifecycle_result.last).not_to eq(main_backend_pid)
      expect(experiment.reload.winner_applied_at).to be_present
      expect(assignment).to be_nil
      expect(experiment.assignments.count).to eq(0)
    ensure
      lifecycle_thread&.kill if lifecycle_thread&.alive?
      stuck_thread = lifecycle_thread if lifecycle_thread && !lifecycle_thread.join(1)
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
      raise Timeout::Error, "并发测试线程未在限定时间内退出" if stuck_thread
    end
  end
end
