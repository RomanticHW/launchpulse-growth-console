require "digest"

class HardenPublishedSnapshotChecksums < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CHECK_CONSTRAINT_NAME = "published_snapshots_checksum_not_blank"
  NOT_NULL_CONSTRAINT_NAME = "published_snapshots_checksum_not_null"
  BLANK_CHECKSUM_PATTERN = "^[[:space:]]*$"
  CHECK_CONSTRAINT_EXPRESSION = "checksum !~ '#{BLANK_CHECKSUM_PATTERN}'"
  NOT_NULL_CONSTRAINT_EXPRESSION = "checksum IS NOT NULL"
  BACKFILL_BATCH_SIZE = 100

  def up
    snapshot_model = Class.new(ActiveRecord::Base) do
      self.table_name = "published_snapshots"
    end
    snapshot_model.reset_column_information

    # NOT VALID 只跳过历史扫描，新写入仍受约束；先封住新脏数据，再分批回填旧记录。
    add_not_valid_constraint_unless_exists(CHECK_CONSTRAINT_NAME, CHECK_CONSTRAINT_EXPRESSION)
    add_not_valid_constraint_unless_exists(NOT_NULL_CONSTRAINT_NAME, NOT_NULL_CONSTRAINT_EXPRESSION)

    snapshot_model
      .where("checksum IS NULL OR checksum ~ ?", BLANK_CHECKSUM_PATTERN)
      .find_each(batch_size: BACKFILL_BATCH_SIZE) do |snapshot|
      snapshot.update_columns(checksum: Digest::SHA256.hexdigest(canonical_json(snapshot.payload)))
    end

    validate_check_constraint :published_snapshots, name: CHECK_CONSTRAINT_NAME
    validate_check_constraint :published_snapshots, name: NOT_NULL_CONSTRAINT_NAME
    # PostgreSQL 可复用已验证的非空 check，避免 SET NOT NULL 再做一次完整表扫描。
    change_column_null :published_snapshots, :checksum, false
    remove_check_constraint :published_snapshots, name: NOT_NULL_CONSTRAINT_NAME, if_exists: true
  end

  def down
    remove_check_constraint :published_snapshots, name: NOT_NULL_CONSTRAINT_NAME, if_exists: true
    remove_check_constraint :published_snapshots, name: CHECK_CONSTRAINT_NAME, if_exists: true
    change_column_null :published_snapshots, :checksum, true
  end

  private

  def add_not_valid_constraint_unless_exists(name, expression)
    return if check_constraint_exists?(:published_snapshots, name:)

    add_check_constraint :published_snapshots,
      expression,
      name:,
      validate: false
  end

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
