require "rails_helper"

RSpec.describe "event aggregation dispatch lease migration" do
  it "adds the dispatch lease and a partial recovery index" do
    column = Event.columns_hash["aggregation_enqueued_at"]
    index = ActiveRecord::Base.connection.indexes(:events).find do |candidate|
      candidate.name == "idx_events_unaggregated_dispatch_recovery"
    end

    expect(column&.type).to eq(:datetime)
    expect(index).to have_attributes(
      columns: %w[created_at aggregation_enqueued_at id],
      where: "(aggregated_at IS NULL)"
    )
  end

  it "uses the recovery index for the created_at grace query" do
    site = create(:site)
    now = Time.current
    old = 5.minutes.ago
    rows = 2_000.times.map do |index|
      created_at = index < 20 ? old : now
      {
        site_id: site.id,
        event_type: "page_view",
        visitor_id: "explain-recovery-#{index}",
        occurred_at: index.even? ? 1.day.from_now : old,
        source: "direct",
        device: "desktop",
        metadata: {},
        created_at:,
        updated_at: created_at,
        aggregation_enqueued_at: index < 20 && index.odd? ? 11.minutes.ago : nil
      }
    end
    Event.insert_all!(rows)
    relation = RequeueUnaggregatedEventsJob.new.send(:eligible_events)
    connection = ActiveRecord::Base.connection
    connection.execute("ANALYZE events")
    connection.execute("SET LOCAL enable_seqscan = off")

    raw_plan = connection.select_value("EXPLAIN (FORMAT JSON) #{relation.to_sql}")
    plan = raw_plan.is_a?(String) ? JSON.parse(raw_plan) : raw_plan
    nodes = plan_nodes(plan.first.fetch("Plan"))
    recovery_node = nodes.find { |node| node["Index Name"] == "idx_events_unaggregated_dispatch_recovery" }

    expect(recovery_node).to be_present, nodes.map { |node| node.slice("Node Type", "Index Name", "Index Cond", "Filter") }.inspect
    expect(recovery_node.fetch("Index Cond")).to include("created_at")
  end

  def plan_nodes(node)
    [ node ] + node.fetch("Plans", []).flat_map { |child| plan_nodes(child) }
  end
end
