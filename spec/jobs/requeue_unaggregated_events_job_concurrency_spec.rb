require "rails_helper"
require "timeout"

RSpec.describe "RequeueUnaggregatedEventsJob concurrency" do
  self.use_transactional_tests = false

  after do
    @site&.destroy!
    @account&.destroy!
    clear_enqueued_jobs
  end

  it "does not enqueue an event twice when two recovery scans overlap" do
    @site = create(:site)
    @account = @site.account
    old = 5.minutes.ago
    event = @site.events.create!(
      event_type: "page_view",
      visitor_id: "concurrent-recovery-visitor",
      occurred_at: old,
      created_at: old,
      updated_at: old
    )
    ready = Queue.new
    release = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          backend_pid = connection.select_value("SELECT pg_backend_pid()")
          ready << true
          release.pop
          RequeueUnaggregatedEventsJob.perform_now
          results << backend_pid
        rescue StandardError => error
          results << error
        end
      end
    end

    2.times { Timeout.timeout(5) { ready.pop } }
    2.times { release << true }
    outcomes = 2.times.map { Timeout.timeout(10) { results.pop } }
    Timeout.timeout(10) { threads.each(&:join) }

    expect(outcomes).to all(be_a(Integer))
    expect(outcomes.uniq.size).to eq(2)
    expect(enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }).to eq([ event.id ])
  ensure
    2.times { release << true } if release
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join(1)
    end
  end
end
