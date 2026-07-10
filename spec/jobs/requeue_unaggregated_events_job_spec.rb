require "rails_helper"

RSpec.describe "RequeueUnaggregatedEventsJob" do
  include ActiveSupport::Testing::TimeHelpers

  def create_event(site:, occurred_at:, created_at:, **attributes)
    site.events.create!({
      event_type: "page_view",
      visitor_id: "recovery-#{SecureRandom.hex(4)}",
      occurred_at:,
      created_at:,
      updated_at: created_at
    }.merge(attributes))
  end

  it "dispatches events old enough by created_at even when occurred_at is in the future" do
    now = Time.current.change(usec: 0)
    old = now - 5.minutes
    site = create(:site)
    eligible = create_event(site:, occurred_at: old, created_at: old)
    expired_lease = create_event(
      site:,
      occurred_at: old,
      created_at: old,
      aggregation_enqueued_at: now - 11.minutes
    )
    future_occurred = create_event(site:, occurred_at: now + 1.day, created_at: old)
    create_event(site:, occurred_at: old, created_at: now)
    create_event(site:, occurred_at: old, created_at: old, aggregated_at: now)
    create_event(site:, occurred_at: old, created_at: old, aggregation_enqueued_at: now - 5.minutes)

    result = nil
    travel_to(now) do
      expect do
        result = RequeueUnaggregatedEventsJob.perform_now
      end.to have_enqueued_job(AggregateEventJob).exactly(3).times
    end

    event_ids = enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }
    expect(event_ids).to contain_exactly(eligible.id, expired_lease.id, future_occurred.id)
    expect(result).to eq(enqueued: 3, skipped: 0, failed: 0)
  end

  it "limits each recovery scan to 500 events" do
    now = Time.current.change(usec: 0)
    old = now - 5.minutes
    site = create(:site)
    rows = 501.times.map do |index|
      {
        site_id: site.id,
        event_type: "page_view",
        visitor_id: "batch-recovery-#{index}",
        source: "direct",
        device: "desktop",
        metadata: {},
        occurred_at: old,
        created_at: old,
        updated_at: old
      }
    end
    Event.insert_all!(rows)

    result = travel_to(now) { RequeueUnaggregatedEventsJob.perform_now }

    expect(enqueued_jobs.count { |job| job[:job] == AggregateEventJob }).to eq(500)
    expect(site.events.where.not(aggregation_enqueued_at: nil).count).to eq(500)
    expect(site.events.where(aggregation_enqueued_at: nil).count).to eq(1)
    expect(result).to eq(enqueued: 500, skipped: 0, failed: 0)
  end

  it "counts skipped and failed dispatches, continues, and logs no event contents" do
    now = Time.current.change(usec: 0)
    site = create(:site)
    false_result = create_event(site:, occurred_at: now - 8.minutes, created_at: now - 8.minutes)
    raised = create_event(site:, occurred_at: now - 7.minutes, created_at: now - 7.minutes)
    skipped = create_event(site:, occurred_at: now - 6.minutes, created_at: now - 6.minutes)
    enqueued = create_event(site:, occurred_at: now - 5.minutes, created_at: now - 5.minutes)
    allow(Events::AggregationDispatcher).to receive(:call).and_wrap_original do |original, event|
      next false if event.id == false_result.id
      raise "sentinel_token=secret sentinel_payload=private" if event.id == raised.id
      next :active_lease if event.id == skipped.id

      original.call(event)
    end
    error_logs = []
    allow(Rails.logger).to receive(:error) { |message| error_logs << message }
    allow(Rails.logger).to receive(:info)

    result = travel_to(now) { RequeueUnaggregatedEventsJob.perform_now }

    expect(result).to eq(enqueued: 1, skipped: 1, failed: 2)
    expect(enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }).to eq([ enqueued.id ])
    expect(error_logs.size).to eq(2)
    expect(error_logs.join(" ")).not_to include("sentinel_token", "secret", "sentinel_payload", "private")
  end
end
