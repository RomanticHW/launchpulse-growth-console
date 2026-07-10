require "rails_helper"

RSpec.describe Analytics::DashboardBroadcaster do
  it "broadcasts event stream and summary updates" do
    site = create(:site)
    event = site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    broadcaster = described_class.new(site)
    broadcaster.broadcast_event(event)
    broadcaster.broadcast_summary

    expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).with(
      "site_#{site.id}_events",
      hash_including(target: "event_stream", partial: "events/event")
    )
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "site_#{site.id}_metrics",
      hash_including(target: "analytics_summary", partial: "sites/analytics_summary")
    )
  end

  it "broadcasts experiment panel updates" do
    site = create(:site)

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    described_class.new(site).broadcast_experiments

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "site_#{site.id}_metrics",
      hash_including(target: "experiments_panel", partial: "sites/experiments")
    )
  end

  it "throttles summary panel broadcasts for the same site" do
    site = create(:site)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    broadcaster = described_class.new(site)
    2.times { broadcaster.broadcast_summary }

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).once.with(
      "site_#{site.id}_metrics",
      hash_including(target: "analytics_summary", partial: "sites/analytics_summary")
    )
  end

  it "throttles experiment panel broadcasts for the same site" do
    site = create(:site)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    broadcaster = described_class.new(site)
    2.times { broadcaster.broadcast_experiments }

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).once.with(
      "site_#{site.id}_metrics",
      hash_including(target: "experiments_panel", partial: "sites/experiments")
    )
  end

  it "schedules a trailing summary refresh when throttled" do
    site = create(:site)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(DashboardRefreshJob).to receive_message_chain(:set, :perform_later)

    broadcaster = described_class.new(site)
    broadcaster.broadcast_summary
    broadcaster.broadcast_summary

    expect(DashboardRefreshJob).to have_received(:set).with(wait: described_class::SUMMARY_THROTTLE_WINDOW)
  end

  it "broadcasts immediately when force is true even if throttled" do
    site = create(:site)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    broadcaster = described_class.new(site)
    broadcaster.broadcast_summary
    broadcaster.broadcast_summary(force: true)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice.with(
      "site_#{site.id}_metrics",
      hash_including(target: "analytics_summary", partial: "sites/analytics_summary")
    )
  end
end
