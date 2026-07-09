class NullifyAnalyticsReferencesOnDestroy < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :events, column: :experiment_id
    remove_foreign_key :events, column: :variant_id
    remove_foreign_key :conversions, column: :event_id

    add_foreign_key :events, :experiments, column: :experiment_id, on_delete: :nullify
    add_foreign_key :events, :variants, column: :variant_id, on_delete: :nullify
    add_foreign_key :conversions, :events, column: :event_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :conversions, column: :event_id
    remove_foreign_key :events, column: :variant_id
    remove_foreign_key :events, column: :experiment_id

    add_foreign_key :conversions, :events, column: :event_id
    add_foreign_key :events, :variants, column: :variant_id
    add_foreign_key :events, :experiments, column: :experiment_id
  end
end
