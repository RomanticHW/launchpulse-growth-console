require "rails_helper"

RSpec.describe PublishedSnapshot do
  def published_snapshot
    site = create(:site, status: "published")
    create(:page, site:)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Integrity spec")
  end

  it "rejects blank checksums" do
    snapshot = published_snapshot

    [ nil, "", " " ].each do |blank_checksum|
      snapshot.checksum = blank_checksum

      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:checksum]).to be_present
    end
  end

  it "defines a non-null checksum column and a non-blank check constraint" do
    checksum_column = described_class.columns_hash.fetch("checksum")
    constraint = described_class.connection
      .check_constraints(:published_snapshots)
      .find { |candidate| candidate.name == "published_snapshots_checksum_not_blank" }

    expect(checksum_column.null).to be(false)
    expect(constraint).to be_present
    expect(constraint.expression).to include("[[:space:]]")
    expect(constraint.options.fetch(:validate)).to be(true)
  end

  {
    "nil" => nil,
    "an empty string" => "",
    "spaces" => "   ",
    "a tab" => "\t",
    "a newline" => "\n"
  }.each do |description, blank_checksum|
    it "rejects #{description} at the database boundary" do
      snapshot = published_snapshot

      expect {
        described_class.where(id: snapshot.id).update_all(checksum: blank_checksum)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
