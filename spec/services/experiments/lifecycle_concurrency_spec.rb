require "rails_helper"
require "timeout"

RSpec.describe Experiments::LifecycleService, "launch and dismiss concurrency" do
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
end
