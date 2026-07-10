class AddPublicRequestTokens < ActiveRecord::Migration[8.1]
  FORM_INDEX_NAME = "idx_form_submissions_unique_request_token"
  ORDER_INDEX_NAME = "idx_orders_unique_request_token"
  FORM_IDENTITY_CONSTRAINT = "form_submissions_request_identity_pair"
  ORDER_IDENTITY_CONSTRAINT = "orders_request_identity_pair"

  def up
    add_column :form_submissions, :request_token, :string
    add_column :form_submissions, :request_fingerprint, :string
    add_column :orders, :request_token, :string
    add_column :orders, :request_fingerprint, :string

    add_check_constraint :form_submissions,
      paired_request_identity_check,
      name: FORM_IDENTITY_CONSTRAINT
    add_check_constraint :orders,
      paired_request_identity_check,
      name: ORDER_IDENTITY_CONSTRAINT

    add_index :form_submissions,
      [ :form_id, :request_token ],
      unique: true,
      where: "request_token IS NOT NULL",
      name: FORM_INDEX_NAME
    add_index :orders,
      [ :site_id, :request_token ],
      unique: true,
      where: "request_token IS NOT NULL",
      name: ORDER_INDEX_NAME
  end

  def down
    remove_index :form_submissions, name: FORM_INDEX_NAME, if_exists: true
    remove_index :orders, name: ORDER_INDEX_NAME, if_exists: true
    remove_check_constraint :form_submissions, name: FORM_IDENTITY_CONSTRAINT, if_exists: true
    remove_check_constraint :orders, name: ORDER_IDENTITY_CONSTRAINT, if_exists: true
    remove_column :form_submissions, :request_fingerprint, if_exists: true
    remove_column :form_submissions, :request_token, if_exists: true
    remove_column :orders, :request_fingerprint, if_exists: true
    remove_column :orders, :request_token, if_exists: true
  end

  private

  def paired_request_identity_check
    <<~SQL.squish
      (request_token IS NULL AND request_fingerprint IS NULL)
      OR (request_token IS NOT NULL AND request_fingerprint IS NOT NULL)
    SQL
  end
end
