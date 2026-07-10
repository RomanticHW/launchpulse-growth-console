module Events
  class AggregationDispatcher
    LEASE_DURATION = 10.minutes

    class << self
      def call(event)
        claimed_at = Time.current
        return false unless claim(event.id, claimed_at)

        enqueue(event.id, claimed_at)
      end

      private

      def claim(event_id, claimed_at)
        Event
          .where(id: event_id, aggregated_at: nil)
          .where("aggregation_enqueued_at IS NULL OR aggregation_enqueued_at < ?", claimed_at - LEASE_DURATION)
          .update_all(aggregation_enqueued_at: claimed_at) == 1
      end

      def enqueue(event_id, claimed_at)
        job = AggregateEventJob.perform_later(event_id)
        return true if job && job.successfully_enqueued?

        release(event_id, claimed_at)
        false
      rescue StandardError
        release(event_id, claimed_at)
        raise
      end

      def release(event_id, claimed_at)
        Event
          .where(id: event_id, aggregated_at: nil, aggregation_enqueued_at: claimed_at)
          .update_all(aggregation_enqueued_at: nil)
      end
    end
  end
end
