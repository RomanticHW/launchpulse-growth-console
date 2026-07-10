require "rails_helper"
require "timeout"

RSpec.describe Experiments::LifecycleService, "lifecycle concurrency" do
  self.use_transactional_tests = false

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

  it "does not assign after complete! obtains the experiment lock first" do
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
          assign_started << true
          begin
            assignment = Experiments::AssignmentService.new(Experiment.find(experiment.id)).assign("visitor-close-first")
            assign_results << [ :ok, assignment&.id, backend_pid ]
          rescue StandardError => error
            assign_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { assign_started.pop }

      assign_result_before_release = begin
        Timeout.timeout(0.5) { assign_results.pop }
      rescue Timeout::Error
        nil
      end
      close_release << true

      close_result = Timeout.timeout(5) { close_results.pop }
      assign_result = assign_result_before_release || Timeout.timeout(5) { assign_results.pop }
      Timeout.timeout(5) do
        close_thread.join
        assign_thread.join
      end

      expect(assign_result_before_release).to be_nil
      expect(close_result.last).not_to eq(assign_result.last)
      expect(close_result.first).to eq(:ok)
      expect(assign_result.first(2)).to eq([ :ok, nil ])
      expect(experiment.reload.status).to eq("completed")
      expect(experiment.assignments.count).to eq(0)
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

  it "allows an assignment that obtains the experiment lock before complete!" do
    site = create(:site)
    account = site.account
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    create(:variant, experiment:, key: "variant")
    assign_ready = Queue.new
    assign_release = Queue.new
    assign_results = Queue.new
    close_started = Queue.new
    close_results = Queue.new
    assign_thread = nil
    close_thread = nil
    gated_assignment_class = Class.new(Experiments::AssignmentService) do
      define_method(:initialize) do |current_experiment, ready:, release:|
        super(current_experiment)
        @ready = ready
        @release = release
      end

      define_method(:weighted_variant_for) do |variants, visitor_id|
        @ready << true
        @release.pop
        super(variants, visitor_id)
      end

      private :weighted_variant_for
    end

    begin
      assign_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          begin
            assignment = gated_assignment_class.new(
              Experiment.find(experiment.id),
              ready: assign_ready,
              release: assign_release
            ).assign("visitor-assign-first")
            assign_results << [ :ok, assignment&.id, backend_pid ]
          rescue StandardError => error
            assign_results << [ :error, error.class, backend_pid ]
          end
        end
      end
      Timeout.timeout(5) { assign_ready.pop }

      close_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          close_started << true
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
      Timeout.timeout(5) { close_started.pop }

      close_result_before_release = begin
        Timeout.timeout(0.5) { close_results.pop }
      rescue Timeout::Error
        nil
      end
      assign_release << true

      assign_result = Timeout.timeout(5) { assign_results.pop }
      close_result = close_result_before_release || Timeout.timeout(5) { close_results.pop }
      Timeout.timeout(5) do
        assign_thread.join
        close_thread.join
      end

      expect(close_result_before_release).to be_nil
      expect(assign_result.last).not_to eq(close_result.last)
      expect(assign_result.first).to eq(:ok)
      expect(assign_result.second).to be_present
      expect(close_result.first).to eq(:ok)
      expect(experiment.reload.status).to eq("completed")
      expect(experiment.assignments.where(visitor_id: "visitor-assign-first").count).to eq(1)
    ensure
      assign_release << true if assign_thread&.alive?
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
