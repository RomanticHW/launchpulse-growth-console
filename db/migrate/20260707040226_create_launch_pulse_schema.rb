class CreateLaunchPulseSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :plan, null: false, default: "demo"
      t.timestamps
    end

    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "owner"
      t.timestamps
    end
    add_index :memberships, [ :account_id, :user_id ], unique: true

    create_table :sites do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :industry, null: false
      t.integer :growth_score, null: false, default: 70
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_index :sites, [ :account_id, :slug ], unique: true

    create_table :pages do |t|
      t.references :site, null: false, foreign_key: true
      t.string :title, null: false
      t.string :path, null: false, default: "/"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pages, [ :site_id, :path ], unique: true

    create_table :sections do |t|
      t.references :page, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :props, null: false, default: {}
      t.timestamps
    end
    add_index :sections, [ :page_id, :position ]
    add_index :sections, :kind

    create_table :published_snapshots do |t|
      t.references :site, null: false, foreign_key: true
      t.references :published_by, foreign_key: { to_table: :users }
      t.integer :version, null: false
      t.jsonb :payload, null: false, default: {}
      t.text :note
      t.timestamps
    end
    add_index :published_snapshots, [ :site_id, :version ], unique: true

    create_table :api_keys do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true

    create_table :events do |t|
      t.references :site, null: false, foreign_key: true
      t.references :page, foreign_key: true
      t.string :event_type, null: false
      t.string :visitor_id, null: false
      t.string :session_id
      t.string :source, null: false, default: "direct"
      t.string :device, null: false, default: "desktop"
      t.string :variant_key
      t.jsonb :metadata, null: false, default: {}
      t.inet :ip_address
      t.string :user_agent
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :events, [ :site_id, :event_type, :occurred_at ]
    add_index :events, [ :site_id, :visitor_id ]
    add_index :events, [ :site_id, :source, :occurred_at ]
    add_index :events, [ :site_id, :device, :occurred_at ]

    create_table :event_rollups do |t|
      t.references :site, null: false, foreign_key: true
      t.date :bucket_date, null: false
      t.string :metric, null: false
      t.string :dimension, null: false, default: "all"
      t.integer :count, null: false, default: 0
      t.timestamps
    end
    add_index :event_rollups, [ :site_id, :bucket_date, :metric, :dimension ], unique: true, name: "idx_event_rollups_unique_bucket"

    create_table :ai_audits do |t|
      t.references :site, null: false, foreign_key: true
      t.string :status, null: false, default: "completed"
      t.integer :score, null: false, default: 0
      t.text :summary
      t.jsonb :input_snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :ai_findings do |t|
      t.references :ai_audit, null: false, foreign_key: true
      t.references :section, foreign_key: true
      t.string :severity, null: false, default: "medium"
      t.string :problem, null: false
      t.text :evidence
      t.timestamps
    end

    create_table :recommendations do |t|
      t.references :site, null: false, foreign_key: true
      t.references :ai_finding, null: false, foreign_key: true
      t.references :section, foreign_key: true
      t.string :title, null: false
      t.text :problem, null: false
      t.jsonb :suggested_patch, null: false, default: {}
      t.string :expected_impact, null: false
      t.decimal :confidence, precision: 4, scale: 2, null: false, default: 0.70
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :recommendations, [ :site_id, :status ]

    create_table :section_patches do |t|
      t.references :recommendation, null: false, foreign_key: true
      t.references :section, null: false, foreign_key: true
      t.jsonb :props_diff, null: false, default: {}
      t.boolean :applied, null: false, default: false
      t.timestamps
    end

    create_table :experiments do |t|
      t.references :site, null: false, foreign_key: true
      t.references :recommendation, foreign_key: true
      t.references :section, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end
    add_index :experiments, [ :site_id, :status ]

    create_table :variants do |t|
      t.references :experiment, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key, null: false
      t.string :role, null: false, default: "variant"
      t.jsonb :props, null: false, default: {}
      t.timestamps
    end
    add_index :variants, [ :experiment_id, :key ], unique: true

    create_table :assignments do |t|
      t.references :experiment, null: false, foreign_key: true
      t.references :variant, null: false, foreign_key: true
      t.string :visitor_id, null: false
      t.timestamps
    end
    add_index :assignments, [ :experiment_id, :visitor_id ], unique: true

    create_table :conversions do |t|
      t.references :assignment, null: false, foreign_key: true
      t.references :event, foreign_key: true
      t.string :conversion_type, null: false, default: "primary"
      t.decimal :value, precision: 10, scale: 2
      t.timestamps
    end

    create_table :forms do |t|
      t.references :site, null: false, foreign_key: true
      t.references :section, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :form_fields do |t|
      t.references :form, null: false, foreign_key: true
      t.string :label, null: false
      t.string :field_type, null: false, default: "text"
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :contacts do |t|
      t.references :site, null: false, foreign_key: true
      t.string :email, null: false
      t.string :name
      t.string :source
      t.timestamps
    end
    add_index :contacts, [ :site_id, :email ], unique: true

    create_table :form_submissions do |t|
      t.references :form, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    create_table :products do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false, default: 0
      t.string :image_url
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :orders do |t|
      t.references :site, null: false, foreign_key: true
      t.string :number, null: false
      t.string :email, null: false
      t.decimal :total, precision: 10, scale: 2, null: false, default: 0
      t.string :source
      t.timestamps
    end
    add_index :orders, [ :site_id, :number ], unique: true

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 10, scale: 2, null: false, default: 0
      t.timestamps
    end

    create_table :audit_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :site, foreign_key: true
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :audit_logs, [ :account_id, :created_at ]
  end
end
