namespace :launch_pulse do
  desc "Enqueue aggregation jobs for events that have not been aggregated"
  task enqueue_unaggregated_events: :environment do
    stats = { enqueued: 0, skipped: 0, failed: 0 }
    Event.where(aggregated_at: nil).find_each do |event|
      status = Events::AggregationDispatcher.call(event)
      if status == :enqueued
        stats[:enqueued] += 1
      elsif Events::AggregationDispatcher::SKIPPED_STATUSES.include?(status)
        stats[:skipped] += 1
      else
        stats[:failed] += 1
      end
    rescue StandardError
      stats[:failed] += 1
    end

    puts "Enqueued #{stats[:enqueued]}; skipped #{stats[:skipped]}; failed #{stats[:failed]} unaggregated events"
  end
end
