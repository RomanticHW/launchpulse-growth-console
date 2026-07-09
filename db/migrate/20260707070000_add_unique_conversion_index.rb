class AddUniqueConversionIndex < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      DELETE FROM conversions
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY assignment_id, conversion_type
                   ORDER BY created_at ASC, id ASC
                 ) AS duplicate_rank
          FROM conversions
        ) ranked_conversions
        WHERE duplicate_rank > 1
      )
    SQL

    add_index :conversions, %i[ assignment_id conversion_type ], unique: true, name: "idx_conversions_unique_assignment_type"
  end

  def down
    remove_index :conversions, name: "idx_conversions_unique_assignment_type"
  end
end
