require "rails_helper"

RSpec.describe Events::MetadataSanitizer do
  it "converts ActionController parameters into plain hashes" do
    params = ActionController::Parameters.new(campaign: "spring", nested: { source: "email" })

    result = described_class.new(params).call

    expect(result).to eq("campaign" => "spring", "nested" => { "source" => "email" })
    expect(result).to be_a(Hash)
  end

  it "rejects top-level arrays" do
    expect do
      described_class.new([ "campaign", "spring" ]).call
    end.to raise_error(Events::MetadataSanitizer::InvalidMetadata, /metadata must be an object/i)
  end

  it "allows nested arrays inside object metadata" do
    result = described_class.new({ campaign: { tags: [ "spring", "vip" ] } }).call

    expect(result).to eq("campaign" => { "tags" => [ "spring", "vip" ] })
  end

  it "rejects metadata that is too deep" do
    metadata = { a: { b: { c: { d: { e: { f: "too deep" } } } } } }

    expect { described_class.new(metadata).call }.to raise_error(Events::MetadataSanitizer::InvalidMetadata, /too deep/i)
  end

  it "rejects oversized metadata" do
    metadata = { payload: "x" * 5.kilobytes }

    expect { described_class.new(metadata).call }.to raise_error(Events::MetadataSanitizer::InvalidMetadata, /too large/i)
  end

  it "rejects hashes with too many keys" do
    metadata = 51.times.each_with_object({}) { |index, result| result["key_#{index}"] = index }

    expect { described_class.new(metadata).call }.to raise_error(Events::MetadataSanitizer::InvalidMetadata, /too many keys/i)
  end
end
