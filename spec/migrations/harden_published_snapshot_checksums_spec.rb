require "rails_helper"
require Rails.root.join("db/migrate/20260709100000_harden_published_snapshot_checksums")

RSpec.describe HardenPublishedSnapshotChecksums do
  it "backfills historical blank checksums and safely reverses the constraints" do
    migration = described_class.new
    snapshot_model = Class.new(ActiveRecord::Base) do
      self.table_name = "published_snapshots"
    end
    site = create(:site)
    account = site.account
    service = Sites::SnapshotService.new(site)
    snapshot_ids = []

    begin
      expect(self.class.use_transactional_tests).to be(true)
      expect(described_class.disable_ddl_transaction).to be(true)

      migration.down
      snapshot_model.reset_column_information
      expect(snapshot_model.columns_hash.fetch("checksum").null).to be(true)
      expect(checksum_constraint_names(snapshot_model)).not_to include(described_class::CHECK_CONSTRAINT_NAME)

      next_version = snapshot_model.where(site_id: site.id).maximum(:version).to_i + 1
      snapshots = [ nil, "", "   ", "\t", "\n" ].each_with_index.map do |checksum, index|
        payload = {
          "site" => { "name" => "Historical #{index}", "id" => site.id },
          "pages" => [ { "path" => "/", "sections" => [ { "props" => { "b" => 2, "a" => 1 } } ] } ]
        }
        snapshot = snapshot_model.create!(
          site_id: site.id,
          version: next_version + index,
          payload:,
          checksum:,
          created_at: Time.current,
          updated_at: Time.current
        )
        snapshot_ids << snapshot.id
        snapshot
      end

      migration_sql = []
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        migration_sql << payload.fetch(:sql)
      end
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        migration.up
      end
      snapshot_model.reset_column_information

      expect(migration_sql.grep(/ADD CONSTRAINT/)).to all(include("NOT VALID"))
      expect(migration_sql.join("\n")).to include("VALIDATE CONSTRAINT")

      snapshots.each do |snapshot|
        snapshot.reload
        expect(snapshot.checksum).to eq(service.send(:checksum_for, snapshot.payload))
        expect(snapshot.checksum).to match(/\A[0-9a-f]{64}\z/)
      end
      expect(snapshot_model.columns_hash.fetch("checksum").null).to be(false)
      expect(checksum_constraint_names(snapshot_model)).to include(described_class::CHECK_CONSTRAINT_NAME)
      expect(checksum_constraint_names(snapshot_model)).not_to include("published_snapshots_checksum_not_null")

      expect do
        ActiveRecord::Base.transaction(requires_new: true) { migration.up }
      end.not_to raise_error

      migration.down
      snapshot_model.reset_column_information
      expect(snapshot_model.columns_hash.fetch("checksum").null).to be(true)
      expect(checksum_constraint_names(snapshot_model)).not_to include(described_class::CHECK_CONSTRAINT_NAME)
    ensure
      migration.down
      snapshot_model.reset_column_information
      snapshot_model.where(id: snapshot_ids).delete_all if snapshot_ids.any?
      migration.up
      snapshot_model.reset_column_information
      site.destroy! if site.persisted?
      account.destroy! if account.persisted?
    end
  end

  def checksum_constraint_names(snapshot_model)
    snapshot_model.connection.check_constraints(:published_snapshots).map(&:name)
  end
end
