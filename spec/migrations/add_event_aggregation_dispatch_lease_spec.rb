require "rails_helper"

RSpec.describe "event aggregation dispatch lease migration" do
  it "adds the dispatch lease and a partial recovery index" do
    column = Event.columns_hash["aggregation_enqueued_at"]
    index = ActiveRecord::Base.connection.indexes(:events).find do |candidate|
      candidate.name == "idx_events_unaggregated_dispatch_recovery"
    end

    expect(column&.type).to eq(:datetime)
    expect(index).to have_attributes(
      columns: %w[occurred_at aggregation_enqueued_at],
      where: "(aggregated_at IS NULL)"
    )
  end
end
