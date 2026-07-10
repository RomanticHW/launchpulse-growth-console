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

  it "dispatches only old unaggregated events with an available lease" do
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
    create_event(site:, occurred_at: now, created_at: old)
    create_event(site:, occurred_at: old, created_at: now)
    create_event(site:, occurred_at: old, created_at: old, aggregated_at: now)
    create_event(site:, occurred_at: old, created_at: old, aggregation_enqueued_at: now - 5.minutes)

    travel_to(now) do
      expect do
        RequeueUnaggregatedEventsJob.perform_now
      end.to have_enqueued_job(AggregateEventJob).exactly(2).times
    end

    event_ids = enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }
    expect(event_ids).to contain_exactly(eligible.id, expired_lease.id)
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

    travel_to(now) { RequeueUnaggregatedEventsJob.perform_now }

    expect(enqueued_jobs.count { |job| job[:job] == AggregateEventJob }).to eq(500)
    expect(site.events.where.not(aggregation_enqueued_at: nil).count).to eq(500)
    expect(site.events.where(aggregation_enqueued_at: nil).count).to eq(1)
  end

  it "continues dispatching after one event fails" do
    now = Time.current.change(usec: 0)
    site = create(:site)
    first = create_event(site:, occurred_at: now - 6.minutes, created_at: now - 6.minutes)
    second = create_event(site:, occurred_at: now - 5.minutes, created_at: now - 5.minutes)
    allow(Events::AggregationDispatcher).to receive(:call).and_wrap_original do |original, event|
      raise "queue unavailable" if event.id == first.id

      original.call(event)
    end
    expect(Rails.logger).to receive(:error).with(/event #{first.id}.*queue unavailable/)

    travel_to(now) do
      expect { RequeueUnaggregatedEventsJob.perform_now }.not_to raise_error
    end

    expect(enqueued_jobs.filter_map { |job| job[:args].first if job[:job] == AggregateEventJob }).to eq([ second.id ])
  end
end
