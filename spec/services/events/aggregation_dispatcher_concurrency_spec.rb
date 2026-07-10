require "rails_helper"
require "timeout"

RSpec.describe "Events::AggregationDispatcher concurrency" do
  self.use_transactional_tests = false

  after do
    @site&.destroy!
    @account&.destroy!
    clear_enqueued_jobs
  end

  it "lets only one database connection claim and enqueue an event" do
    @site = create(:site)
    @account = @site.account
    event = @site.events.create!(
      event_type: "page_view",
      visitor_id: "concurrent-dispatcher-visitor",
      occurred_at: Time.current
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
          claimed = Events::AggregationDispatcher.call(Event.find(event.id))
          results << [ claimed, backend_pid ]
        rescue StandardError => error
          results << [ error, backend_pid ]
        end
      end
    end

    2.times { Timeout.timeout(5) { ready.pop } }
    2.times { release << true }
    outcomes = 2.times.map { Timeout.timeout(10) { results.pop } }
    Timeout.timeout(10) { threads.each(&:join) }

    expect(outcomes.map(&:last).uniq.size).to eq(2)
    expect(outcomes.map(&:first)).to contain_exactly(true, false)
    expect(enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }).to eq([ event.id ])
  ensure
    2.times { release << true } if release
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join(1)
    end
  end
end
