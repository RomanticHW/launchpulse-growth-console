require "digest"

class HardenPublishedSnapshotChecksums < ActiveRecord::Migration[8.1]
  CHECK_CONSTRAINT_NAME = "published_snapshots_checksum_not_blank"

  def up
    snapshot_model = Class.new(ActiveRecord::Base) do
      self.table_name = "published_snapshots"
    end
    snapshot_model.reset_column_information

    snapshot_model.where("checksum IS NULL OR BTRIM(checksum) = ''").find_each do |snapshot|
      snapshot.update_columns(checksum: Digest::SHA256.hexdigest(canonical_json(snapshot.payload)))
    end

    change_column_null :published_snapshots, :checksum, false
    add_check_constraint :published_snapshots,
      "BTRIM(checksum) <> ''",
      name: CHECK_CONSTRAINT_NAME
  end

  def down
    remove_check_constraint :published_snapshots, name: CHECK_CONSTRAINT_NAME, if_exists: true
    change_column_null :published_snapshots, :checksum, true
  end

  private

  def canonical_json(value)
    JSON.generate(canonicalize(value))
  end

  def canonicalize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), result|
        result[key.to_s] = canonicalize(nested_value)
      end.sort.to_h
    when Array
      value.map { |nested_value| canonicalize(nested_value) }
    when Time, DateTime
      value.iso8601(6)
    when Date
      value.iso8601
    when String, Numeric, TrueClass, FalseClass, NilClass
      value
    else
      value.to_s
    end
  end
end
