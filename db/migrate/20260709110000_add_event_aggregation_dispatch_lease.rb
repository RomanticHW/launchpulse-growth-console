class AddEventAggregationDispatchLease < ActiveRecord::Migration[8.1]
  INDEX_NAME = "idx_events_unaggregated_dispatch_recovery"

  def up
    add_column :events, :aggregation_enqueued_at, :datetime unless column_exists?(:events, :aggregation_enqueued_at)
    return if index_exists?(:events, [ :created_at, :aggregation_enqueued_at, :id ], name: INDEX_NAME)

    add_index :events,
      [ :created_at, :aggregation_enqueued_at, :id ],
      where: "aggregated_at IS NULL",
      name: INDEX_NAME
  end

  def down
    remove_index :events, name: INDEX_NAME, if_exists: true
    remove_column :events, :aggregation_enqueued_at, if_exists: true
  end
end
