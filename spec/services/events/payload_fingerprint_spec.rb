require "rails_helper"

RSpec.describe Events::PayloadFingerprint do
  it "keeps numeric metadata distinct from string metadata" do
    numeric = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { count: 1 })
    string = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { count: "1" })

    expect(numeric).not_to eq(string)
  end

  it "keeps boolean metadata distinct from string metadata" do
    boolean = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { enabled: false })
    string = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { enabled: "false" })

    expect(boolean).not_to eq(string)
  end

  it "is stable regardless of hash key ordering" do
    first = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { b: 2, a: 1 })
    second = described_class.call(visitor_id: "v1", event_type: "page_view", metadata: { a: 1, b: 2 })

    expect(first).to eq(second)
  end

  it "is stable for nested metadata key ordering" do
    first = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { outer: { b: 2, a: 1 } })
    second = described_class.call(event_type: "page_view", visitor_id: "v1", metadata: { outer: { a: 1, b: 2 } })

    expect(first).to eq(second)
  end

  it "normalizes parseable occurred_at values to the same instant" do
    first = described_class.call(event_type: "page_view", visitor_id: "v1", occurred_at: "2026-07-07T10:00:00Z")
    second = described_class.call(event_type: "page_view", visitor_id: "v1", occurred_at: "2026-07-07 10:00:00 UTC")

    expect(first).to eq(second)
  end

  it "changes when section uid changes" do
    first = described_class.call(event_type: "cta_click", visitor_id: "v1", section_uid: "section-a")
    second = described_class.call(event_type: "cta_click", visitor_id: "v1", section_uid: "section-b")

    expect(first).not_to eq(second)
  end
end
