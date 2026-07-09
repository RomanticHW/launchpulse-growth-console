require "rails_helper"

RSpec.describe Analytics::DashboardSummaryCollection do
  it "matches dashboard card metrics for multiple sites while preserving rollup semantics" do
    account = create(:account)
    rolled_site = create(:site, account:)
    raw_site = create(:site, account:)
    rolled_site.event_rollups.create!(bucket_date: Date.current, metric: "event:page_view", dimension: "all", count: 10)
    rolled_site.events.create!(event_type: "page_view", visitor_id: "rolled-unaggregated", source: "direct", device: "desktop", occurred_at: Time.current)
    rolled_site.events.create!(event_type: "form_submit", visitor_id: "rolled-unaggregated", source: "direct", device: "desktop", occurred_at: Time.current)
    raw_site.events.create!(event_type: "page_view", visitor_id: "raw-visitor", source: "direct", device: "desktop", occurred_at: Time.current)
    raw_site.events.create!(event_type: "order_created", visitor_id: "raw-visitor", source: "direct", device: "desktop", occurred_at: Time.current)

    summaries = described_class.new([ rolled_site, raw_site ]).call

    expect(summaries.fetch(rolled_site.id)).to include(page_views: 11, conversion_rate: 100.to_d)
    expect(summaries.fetch(raw_site.id)).to include(page_views: 1, conversion_rate: 100.to_d)
  end

  it "builds a per-site conversion trend for dashboard sparklines" do
    site = create(:site)
    page = create(:page, site:)
    first_day = 2.days.ago.change(hour: 10)
    second_day = 1.day.ago.change(hour: 10)

    site.events.create!(page:, event_type: "page_view", visitor_id: "visitor-a", source: "direct", device: "desktop", occurred_at: first_day)
    site.events.create!(page:, event_type: "form_submit", visitor_id: "visitor-a", source: "direct", device: "desktop", occurred_at: first_day + 10.minutes)
    site.events.create!(page:, event_type: "page_view", visitor_id: "visitor-b", source: "direct", device: "desktop", occurred_at: second_day)
    site.events.create!(page:, event_type: "page_view", visitor_id: "visitor-c", source: "direct", device: "mobile", occurred_at: second_day)
    site.events.create!(page:, event_type: "order_created", visitor_id: "visitor-b", source: "direct", device: "desktop", occurred_at: second_day + 10.minutes)

    trend = described_class.new([ site ], since: 2.days.ago.beginning_of_day).call.fetch(site.id).fetch(:conversion_trend)

    expect(trend).to be_an(Array)
    expect(trend.last(3)).to eq([ 100.to_d, 50.to_d, 0.to_d ])
  end
end
