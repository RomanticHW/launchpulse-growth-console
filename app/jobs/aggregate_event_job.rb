class AggregateEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = Event.find(event_id)
    Analytics::AggregationService.new(event).call
  end
end
