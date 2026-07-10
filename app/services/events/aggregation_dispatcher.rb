module Events
  class AggregationDispatcher
    LEASE_DURATION = 10.minutes
    SKIPPED_STATUSES = %i[active_lease already_aggregated not_found].freeze

    class << self
      def call(event)
        claimed_at = Time.current
        return skipped_status(event.id) unless claim(event.id, claimed_at)

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
        return :enqueued if job && job.successfully_enqueued?

        release(event_id, claimed_at)
        :enqueue_failed
      rescue StandardError
        release(event_id, claimed_at)
        raise
      end

      def release(event_id, claimed_at)
        Event
          .where(id: event_id, aggregated_at: nil, aggregation_enqueued_at: claimed_at)
          .update_all(aggregation_enqueued_at: nil)
      end

      def skipped_status(event_id)
        state = Event.where(id: event_id).pick(:aggregated_at, :aggregation_enqueued_at)
        return :not_found unless state
        return :already_aggregated if state.first

        :active_lease
      end
    end
  end
end
