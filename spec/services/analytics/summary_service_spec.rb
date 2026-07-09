require "rails_helper"

RSpec.describe Analytics::SummaryService do
  it "uses page view rollups for source and device summaries when rollups exist" do
    site = create(:site)
    site.events.create!(event_type: "page_view", visitor_id: "visitor-1", source: "direct", device: "desktop", occurred_at: Time.current, aggregated_at: Time.current)
    site.event_rollups.create!(bucket_date: Date.current, metric: "event:page_view", dimension: "all", count: 10)
    site.event_rollups.create!(bucket_date: Date.current, metric: "source", dimension: "paid", count: 50)
    site.event_rollups.create!(bucket_date: Date.current, metric: "page_view_source", dimension: "search", count: 7)
    site.event_rollups.create!(bucket_date: Date.current, metric: "page_view_device", dimension: "mobile", count: 6)

    summary = described_class.new(site).call

    expect(summary.fetch(:page_views)).to eq(10)
    expect(summary.fetch(:top_sources)).to eq("search" => 7)
    expect(summary.fetch(:top_devices)).to eq("mobile" => 6)
  end

  it "combines rollups with unaggregated raw events" do
    site = create(:site)
    site.event_rollups.create!(bucket_date: Date.current, metric: "event:page_view", dimension: "all", count: 10)
    site.event_rollups.create!(bucket_date: Date.current, metric: "page_view_source", dimension: "search", count: 7)
    site.event_rollups.create!(bucket_date: Date.current, metric: "page_view_device", dimension: "mobile", count: 6)
    site.events.create!(event_type: "page_view", visitor_id: "visitor-raw", source: "direct", device: "desktop", occurred_at: Time.current)
    site.events.create!(event_type: "order_created", visitor_id: "visitor-order", source: "paid", device: "tablet", occurred_at: Time.current)

    summary = described_class.new(site).call

    expect(summary.fetch(:page_views)).to eq(11)
    expect(summary.fetch(:top_sources)).to eq("search" => 7, "direct" => 1)
    expect(summary.fetch(:top_devices)).to eq("mobile" => 6, "desktop" => 1)
  end

  it "falls back to raw events when rollups are absent" do
    site = create(:site)
    site.events.create!(event_type: "page_view", visitor_id: "visitor-1", source: "direct", device: "desktop", occurred_at: Time.current)
    3.times { |index| site.events.create!(event_type: "order_created", visitor_id: "visitor-order-#{index}", source: "paid", device: "mobile", occurred_at: Time.current) }

    summary = described_class.new(site).call

    expect(summary.fetch(:page_views)).to eq(1)
    expect(summary.fetch(:top_sources)).to eq("direct" => 1)
    expect(summary.fetch(:top_devices)).to eq("desktop" => 1)
  end
end
