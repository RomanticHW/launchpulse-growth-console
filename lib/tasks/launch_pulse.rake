namespace :launch_pulse do
  desc "Enqueue aggregation jobs for events that have not been aggregated"
  task enqueue_unaggregated_events: :environment do
    count = 0
    Event.where(aggregated_at: nil).find_each do |event|
      AggregateEventJob.perform_later(event.id)
      count += 1
    end

    puts "Enqueued #{count} unaggregated events"
  end
end
