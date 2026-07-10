namespace :launch_pulse do
  desc "Enqueue aggregation jobs for events that have not been aggregated"
  task enqueue_unaggregated_events: :environment do
    claimed = 0
    enqueued = 0
    Event.where(aggregated_at: nil).find_each do |event|
      next unless Events::AggregationDispatcher.call(event)

      claimed += 1
      enqueued += 1
    end

    puts "Claimed #{claimed}; enqueued #{enqueued} unaggregated events"
  end
end
