class AddStableRuntimeKeys < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :key, :string
    add_column :form_fields, :key, :string
    add_column :form_fields, :metadata, :jsonb, null: false, default: {}
    add_reference :experiments, :winner_variant, foreign_key: { to_table: :variants }
    add_column :experiments, :winner_applied_at, :datetime

    say_with_time "Backfilling product and form field keys" do
      product_model = Class.new(ActiveRecord::Base) do
        self.table_name = "products"
      end
      form_field_model = Class.new(ActiveRecord::Base) do
        self.table_name = "form_fields"
      end

      # 使用匿名模型，避免后续业务模型变化影响历史迁移。
      product_model.reset_column_information
      product_model.find_each do |product|
        product.update_columns(key: unique_key_for(product_model.where(site_id: product.site_id).where.not(id: product.id), product.name.to_s.parameterize))
      end

      form_field_model.reset_column_information
      form_field_model.find_each do |field|
        field.update_columns(key: unique_key_for(form_field_model.where(form_id: field.form_id).where.not(id: field.id), field.label.to_s.parameterize.underscore))
      end
    end

    change_column_null :products, :key, false
    change_column_null :form_fields, :key, false
    add_index :products, [ :site_id, :key ], unique: true
    add_index :form_fields, [ :form_id, :key ], unique: true
  end

  def down
    remove_index :form_fields, [ :form_id, :key ]
    remove_index :products, [ :site_id, :key ]
    remove_column :experiments, :winner_applied_at
    remove_reference :experiments, :winner_variant, foreign_key: { to_table: :variants }
    remove_column :form_fields, :metadata
    remove_column :form_fields, :key
    remove_column :products, :key
  end

  private

  def unique_key_for(scope, base)
    root = base.presence || "item"
    candidate = root
    index = 2
    while scope.where(key: candidate).exists?
      candidate = "#{root}-#{index}"
      index += 1
    end
    candidate
  end
end
