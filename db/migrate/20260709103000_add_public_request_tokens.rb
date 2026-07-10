class AddPublicRequestTokens < ActiveRecord::Migration[8.1]
  FORM_INDEX_NAME = "idx_form_submissions_unique_request_token"
  ORDER_INDEX_NAME = "idx_orders_unique_request_token"

  def up
    add_column :form_submissions, :request_token, :string
    add_column :orders, :request_token, :string

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
    remove_column :form_submissions, :request_token, if_exists: true
    remove_column :orders, :request_token, if_exists: true
  end
end
