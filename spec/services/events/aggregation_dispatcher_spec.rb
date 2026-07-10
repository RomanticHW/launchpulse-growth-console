require "rails_helper"

RSpec.describe "Events::AggregationDispatcher" do
  def create_event(**attributes)
    create(:site).events.create!({
      event_type: "page_view",
      visitor_id: "dispatcher-visitor",
      occurred_at: Time.current
    }.merge(attributes))
  end

  it "claims an unaggregated event and enqueues its aggregation job" do
    event = create_event

    result = nil
    expect do
      result = Events::AggregationDispatcher.call(event)
    end.to have_enqueued_job(AggregateEventJob).with(event.id).once

    expect(result).to be(true)
    expect(event.reload.aggregation_enqueued_at).to be_within(1.second).of(Time.current)
  end

  it "does not enqueue the same event again while its lease is active" do
    event = create_event

    results = nil
    expect do
      results = 2.times.map { Events::AggregationDispatcher.call(event) }
    end.to have_enqueued_job(AggregateEventJob).with(event.id).once

    expect(results).to eq([ true, false ])
  end

  it "reclaims an event after its enqueue lease expires" do
    event = create_event(aggregation_enqueued_at: 11.minutes.ago)

    expect do
      expect(Events::AggregationDispatcher.call(event)).to be(true)
    end.to have_enqueued_job(AggregateEventJob).with(event.id).once

    expect(event.reload.aggregation_enqueued_at).to be_within(1.second).of(Time.current)
  end

  it "does nothing after the event has been aggregated" do
    event = create_event(aggregated_at: Time.current, aggregation_enqueued_at: 11.minutes.ago)

    expect(Events::AggregationDispatcher.call(event)).to be(false)
    expect(enqueued_jobs).to be_empty
  end

  it "releases its claim and reraises when enqueue raises" do
    event = create_event
    allow(AggregateEventJob).to receive(:perform_later).and_raise("queue unavailable")

    expect do
      Events::AggregationDispatcher.call(event)
    end.to raise_error(RuntimeError, "queue unavailable")

    expect(event.reload.aggregation_enqueued_at).to be_nil
  end

  it "releases its claim and returns false when enqueue is unsuccessful" do
    event = create_event
    allow(AggregateEventJob).to receive(:perform_later).and_return(false)

    expect(Events::AggregationDispatcher.call(event)).to be(false)

    expect(event.reload.aggregation_enqueued_at).to be_nil
  end
end
