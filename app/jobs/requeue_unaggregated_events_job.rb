class RequeueUnaggregatedEventsJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 2.minutes
  BATCH_LIMIT = 500

  def perform
    stats = { enqueued: 0, skipped: 0, failed: 0 }
    eligible_events.each do |event|
      record_status(stats, event, Events::AggregationDispatcher.call(event))
    rescue StandardError => error
      stats[:failed] += 1
      Rails.logger.error("Aggregation recovery failed for event #{event.id} (#{error.class.name})")
    end
    Rails.logger.info("Aggregation recovery completed: enqueued=#{stats[:enqueued]} skipped=#{stats[:skipped]} failed=#{stats[:failed]}")
    stats
  end

  private

  def eligible_events
    now = Time.current
    grace_cutoff = now - GRACE_PERIOD
    lease_cutoff = now - Events::AggregationDispatcher::LEASE_DURATION

    Event
      .where(aggregated_at: nil)
      .where("created_at <= ?", grace_cutoff)
      .where("aggregation_enqueued_at IS NULL OR aggregation_enqueued_at < ?", lease_cutoff)
      .order(:id)
      .limit(BATCH_LIMIT)
  end

  def record_status(stats, event, status)
    case status
    when :enqueued
      stats[:enqueued] += 1
    when *Events::AggregationDispatcher::SKIPPED_STATUSES
      stats[:skipped] += 1
    else
      stats[:failed] += 1
      Rails.logger.error("Aggregation recovery failed for event #{event.id} (enqueue unsuccessful)")
    end
  end
end
