class AddGrowthLoopRuntimeFields < ActiveRecord::Migration[8.1]
  def up
    add_column :sections, :uid, :string
    section_model = Class.new(ActiveRecord::Base) do
      self.table_name = "sections"
    end
    # 迁移只依赖当前表结构，避免后续模型验证或回调导致历史迁移失败。
    section_model.reset_column_information
    section_model.find_each do |section|
      section.update_columns(uid: SecureRandom.uuid)
    end
    change_column_null :sections, :uid, false
    add_index :sections, :uid, unique: true

    add_column :published_snapshots, :checksum, :string
    add_column :published_snapshots, :published_at, :datetime

    add_reference :events, :experiment, foreign_key: true
    add_reference :events, :variant, foreign_key: true
    add_column :events, :idempotency_key, :string
    add_column :events, :aggregated_at, :datetime
    add_index :events, [ :site_id, :occurred_at ]
    add_index :events, [ :site_id, :visitor_id, :event_type ]
    add_index :events, [ :site_id, :variant_key, :event_type, :occurred_at ], name: "idx_events_variant_queries"
    add_index :events, [ :site_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL", name: "idx_events_idempotency"

    add_column :section_patches, :status, :string, null: false, default: "pending"
    add_column :section_patches, :before_props, :jsonb, null: false, default: {}
    add_column :section_patches, :after_props, :jsonb, null: false, default: {}
    add_column :section_patches, :applied_at, :datetime
    add_column :section_patches, :reverted_at, :datetime

    add_column :recommendations, :dismissed_at, :datetime
    add_column :recommendations, :applied_at, :datetime

    add_column :variants, :weight, :integer, null: false, default: 50
  end

  def down
    remove_column :variants, :weight
    remove_column :recommendations, :applied_at
    remove_column :recommendations, :dismissed_at

    remove_column :section_patches, :reverted_at
    remove_column :section_patches, :applied_at
    remove_column :section_patches, :after_props
    remove_column :section_patches, :before_props
    remove_column :section_patches, :status

    remove_index :events, name: "idx_events_idempotency"
    remove_index :events, name: "idx_events_variant_queries"
    remove_index :events, [ :site_id, :visitor_id, :event_type ]
    remove_index :events, [ :site_id, :occurred_at ]
    remove_column :events, :aggregated_at
    remove_column :events, :idempotency_key
    remove_reference :events, :variant, foreign_key: true
    remove_reference :events, :experiment, foreign_key: true

    remove_column :published_snapshots, :published_at
    remove_column :published_snapshots, :checksum

    remove_index :sections, :uid
    remove_column :sections, :uid
  end
end
