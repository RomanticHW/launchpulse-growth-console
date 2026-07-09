class HardenExperimentWinnersAndConversionDefaults < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :experiments, column: :winner_variant_id
    add_foreign_key :experiments, :variants, column: :winner_variant_id, on_delete: :nullify

    conversion_model = Class.new(ActiveRecord::Base) do
      self.table_name = "conversions"
    end
    conversion_model.where(conversion_type: "primary").update_all(conversion_type: "form_submit")
    change_column_default :conversions, :conversion_type, from: "primary", to: nil
  end

  def down
    change_column_default :conversions, :conversion_type, from: nil, to: "primary"
    remove_foreign_key :experiments, column: :winner_variant_id
    add_foreign_key :experiments, :variants, column: :winner_variant_id
  end
end
