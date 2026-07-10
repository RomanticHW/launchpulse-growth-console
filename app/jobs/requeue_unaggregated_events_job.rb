class RequeueUnaggregatedEventsJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 2.minutes
  BATCH_LIMIT = 500

  def perform
    eligible_events.count do |event|
      Events::AggregationDispatcher.call(event)
    rescue StandardError => error
      Rails.logger.error(
        "Aggregation recovery failed for event #{event.id}: #{error.class}: #{error.message}"
      )
      false
    end
  end

  private

  def eligible_events
    now = Time.current
    grace_cutoff = now - GRACE_PERIOD
    lease_cutoff = now - Events::AggregationDispatcher::LEASE_DURATION

    Event
      .where(aggregated_at: nil)
      .where("occurred_at <= ? AND created_at <= ?", grace_cutoff, grace_cutoff)
      .where("aggregation_enqueued_at IS NULL OR aggregation_enqueued_at < ?", lease_cutoff)
      .order(:occurred_at, :id)
      .limit(BATCH_LIMIT)
  end
end
