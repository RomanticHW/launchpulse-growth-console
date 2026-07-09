class AddUnaggregatedEventsIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :events, :aggregated_at,
      where: "aggregated_at IS NULL",
      name: "index_events_unaggregated"
  end
end
