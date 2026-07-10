# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_09_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "plan", default: "demo", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ai_audits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "input_snapshot", default: {}, null: false
    t.integer "score", default: 0, null: false
    t.bigint "site_id", null: false
    t.string "status", default: "completed", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_ai_audits_on_site_id"
  end

  create_table "ai_findings", force: :cascade do |t|
    t.bigint "ai_audit_id", null: false
    t.datetime "created_at", null: false
    t.text "evidence"
    t.string "problem", null: false
    t.bigint "section_id"
    t.string "severity", default: "medium", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_audit_id"], name: "index_ai_findings_on_ai_audit_id"
    t.index ["section_id"], name: "index_ai_findings_on_section_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "site_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_api_keys_on_site_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "experiment_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", null: false
    t.string "visitor_id", null: false
    t.index ["experiment_id", "visitor_id"], name: "index_assignments_on_experiment_id_and_visitor_id", unique: true
    t.index ["experiment_id"], name: "index_assignments_on_experiment_id"
    t.index ["variant_id"], name: "index_assignments_on_variant_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "site_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["account_id", "created_at"], name: "index_audit_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_audit_logs_on_account_id"
    t.index ["site_id"], name: "index_audit_logs_on_site_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.bigint "site_id", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.index ["site_id", "email"], name: "index_contacts_on_site_id_and_email", unique: true
    t.index ["site_id"], name: "index_contacts_on_site_id"
  end

  create_table "conversions", force: :cascade do |t|
    t.bigint "assignment_id", null: false
    t.string "conversion_type", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 10, scale: 2
    t.index ["assignment_id", "conversion_type"], name: "idx_conversions_unique_assignment_type", unique: true
    t.index ["assignment_id"], name: "index_conversions_on_assignment_id"
    t.index ["event_id"], name: "index_conversions_on_event_id"
  end

  create_table "event_rollups", force: :cascade do |t|
    t.date "bucket_date", null: false
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "dimension", default: "all", null: false
    t.string "metric", null: false
    t.bigint "site_id", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "bucket_date", "metric", "dimension"], name: "idx_event_rollups_unique_bucket", unique: true
    t.index ["site_id"], name: "index_event_rollups_on_site_id"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "aggregated_at"
    t.datetime "created_at", null: false
    t.string "device", default: "desktop", null: false
    t.string "event_type", null: false
    t.bigint "experiment_id"
    t.string "idempotency_key"
    t.inet "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.bigint "page_id"
    t.string "payload_fingerprint"
    t.string "session_id"
    t.bigint "site_id", null: false
    t.string "source", default: "direct", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "variant_id"
    t.string "variant_key"
    t.string "visitor_id", null: false
    t.index ["aggregated_at"], name: "index_events_unaggregated", where: "(aggregated_at IS NULL)"
    t.index ["experiment_id"], name: "index_events_on_experiment_id"
    t.index ["page_id"], name: "index_events_on_page_id"
    t.index ["site_id", "device", "occurred_at"], name: "index_events_on_site_id_and_device_and_occurred_at"
    t.index ["site_id", "event_type", "occurred_at"], name: "index_events_on_site_id_and_event_type_and_occurred_at"
    t.index ["site_id", "idempotency_key"], name: "idx_events_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["site_id", "occurred_at"], name: "index_events_on_site_id_and_occurred_at"
    t.index ["site_id", "payload_fingerprint"], name: "index_events_on_site_id_and_payload_fingerprint"
    t.index ["site_id", "source", "occurred_at"], name: "index_events_on_site_id_and_source_and_occurred_at"
    t.index ["site_id", "variant_key", "event_type", "occurred_at"], name: "idx_events_variant_queries"
    t.index ["site_id", "visitor_id", "event_type"], name: "index_events_on_site_id_and_visitor_id_and_event_type"
    t.index ["site_id", "visitor_id"], name: "index_events_on_site_id_and_visitor_id"
    t.index ["site_id"], name: "index_events_on_site_id"
    t.index ["variant_id"], name: "index_events_on_variant_id"
  end

  create_table "experiments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "name", null: false
    t.string "primary_goal", default: "form_submit", null: false
    t.bigint "recommendation_id"
    t.bigint "section_id"
    t.bigint "site_id", null: false
    t.datetime "started_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.datetime "winner_applied_at"
    t.bigint "winner_variant_id"
    t.index ["primary_goal"], name: "index_experiments_on_primary_goal"
    t.index ["recommendation_id"], name: "index_experiments_on_recommendation_id"
    t.index ["section_id"], name: "index_experiments_on_section_id"
    t.index ["site_id", "status"], name: "index_experiments_on_site_id_and_status"
    t.index ["site_id"], name: "index_experiments_on_site_id"
    t.index ["winner_variant_id"], name: "index_experiments_on_winner_variant_id"
  end

  create_table "form_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "field_type", default: "text", null: false
    t.bigint "form_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["form_id", "key"], name: "index_form_fields_on_form_id_and_key", unique: true
    t.index ["form_id"], name: "index_form_fields_on_form_id"
  end

  create_table "form_submissions", force: :cascade do |t|
    t.bigint "contact_id"
    t.datetime "created_at", null: false
    t.bigint "form_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_form_submissions_on_contact_id"
    t.index ["form_id"], name: "index_form_submissions_on_form_id"
  end

  create_table "forms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "section_id"
    t.bigint "site_id", null: false
    t.datetime "updated_at", null: false
    t.index ["section_id"], name: "index_forms_on_section_id"
    t.index ["site_id"], name: "index_forms_on_site_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "owner", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "user_id"], name: "index_memberships_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_memberships_on_account_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "unit_price", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "number", null: false
    t.bigint "site_id", null: false
    t.string "source"
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "number"], name: "index_orders_on_site_id_and_number", unique: true
    t.index ["site_id"], name: "index_orders_on_site_id"
  end

  create_table "pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "path", default: "/", null: false
    t.integer "position", default: 0, null: false
    t.bigint "site_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "path"], name: "index_pages_on_site_id_and_path", unique: true
    t.index ["site_id"], name: "index_pages_on_site_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "image_url"
    t.string "key", null: false
    t.string "name", null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "site_id", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "key"], name: "index_products_on_site_id_and_key", unique: true
    t.index ["site_id"], name: "index_products_on_site_id"
  end

  create_table "published_snapshots", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.jsonb "payload", default: {}, null: false
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.bigint "site_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["published_by_id"], name: "index_published_snapshots_on_published_by_id"
    t.index ["site_id", "version"], name: "index_published_snapshots_on_site_id_and_version", unique: true
    t.index ["site_id"], name: "index_published_snapshots_on_site_id"
    t.check_constraint "btrim(checksum::text) <> ''::text", name: "published_snapshots_checksum_not_blank"
  end

  create_table "recommendations", force: :cascade do |t|
    t.bigint "ai_finding_id", null: false
    t.datetime "applied_at"
    t.decimal "confidence", precision: 4, scale: 2, default: "0.7", null: false
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.string "expected_impact", null: false
    t.text "problem", null: false
    t.bigint "section_id"
    t.bigint "site_id", null: false
    t.string "status", default: "open", null: false
    t.jsonb "suggested_patch", default: {}, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_finding_id"], name: "index_recommendations_on_ai_finding_id"
    t.index ["section_id"], name: "index_recommendations_on_section_id"
    t.index ["site_id", "status"], name: "index_recommendations_on_site_id_and_status"
    t.index ["site_id"], name: "index_recommendations_on_site_id"
  end

  create_table "section_patches", force: :cascade do |t|
    t.jsonb "after_props", default: {}, null: false
    t.boolean "applied", default: false, null: false
    t.datetime "applied_at"
    t.jsonb "before_props", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "props_diff", default: {}, null: false
    t.bigint "recommendation_id", null: false
    t.datetime "reverted_at"
    t.bigint "section_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["recommendation_id"], name: "index_section_patches_on_recommendation_id"
    t.index ["section_id"], name: "index_section_patches_on_section_id"
  end

  create_table "sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.bigint "page_id", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "props", default: {}, null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_sections_on_kind"
    t.index ["page_id", "position"], name: "index_sections_on_page_id_and_position"
    t.index ["page_id"], name: "index_sections_on_page_id"
    t.index ["uid"], name: "index_sections_on_uid", unique: true
  end

  create_table "sites", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.integer "growth_score", default: 70, null: false
    t.string "industry", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sites_on_account_id"
    t.index ["slug"], name: "index_sites_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "variants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "experiment_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.jsonb "props", default: {}, null: false
    t.string "role", default: "variant", null: false
    t.datetime "updated_at", null: false
    t.integer "weight", default: 50, null: false
    t.index ["experiment_id", "key"], name: "index_variants_on_experiment_id_and_key", unique: true
    t.index ["experiment_id"], name: "index_variants_on_experiment_id"
  end

  add_foreign_key "ai_audits", "sites"
  add_foreign_key "ai_findings", "ai_audits"
  add_foreign_key "ai_findings", "sections"
  add_foreign_key "api_keys", "sites"
  add_foreign_key "assignments", "experiments"
  add_foreign_key "assignments", "variants"
  add_foreign_key "audit_logs", "accounts"
  add_foreign_key "audit_logs", "sites"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "contacts", "sites"
  add_foreign_key "conversions", "assignments"
  add_foreign_key "conversions", "events", on_delete: :nullify
  add_foreign_key "event_rollups", "sites"
  add_foreign_key "events", "experiments", on_delete: :nullify
  add_foreign_key "events", "pages"
  add_foreign_key "events", "sites"
  add_foreign_key "events", "variants", on_delete: :nullify
  add_foreign_key "experiments", "recommendations"
  add_foreign_key "experiments", "sections"
  add_foreign_key "experiments", "sites"
  add_foreign_key "experiments", "variants", column: "winner_variant_id", on_delete: :nullify
  add_foreign_key "form_fields", "forms"
  add_foreign_key "form_submissions", "contacts"
  add_foreign_key "form_submissions", "forms"
  add_foreign_key "forms", "sections"
  add_foreign_key "forms", "sites"
  add_foreign_key "memberships", "accounts"
  add_foreign_key "memberships", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "sites"
  add_foreign_key "pages", "sites"
  add_foreign_key "products", "sites"
  add_foreign_key "published_snapshots", "sites"
  add_foreign_key "published_snapshots", "users", column: "published_by_id"
  add_foreign_key "recommendations", "ai_findings"
  add_foreign_key "recommendations", "sections"
  add_foreign_key "recommendations", "sites"
  add_foreign_key "section_patches", "recommendations"
  add_foreign_key "section_patches", "sections"
  add_foreign_key "sections", "pages"
  add_foreign_key "sites", "accounts"
  add_foreign_key "variants", "experiments"
end
