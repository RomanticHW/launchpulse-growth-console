class AddEventPayloadFingerprint < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :payload_fingerprint, :string
    add_index :events, [ :site_id, :payload_fingerprint ]
  end
end
