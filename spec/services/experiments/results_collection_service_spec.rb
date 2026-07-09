require "rails_helper"

RSpec.describe Experiments::ResultsCollectionService do
  it "returns per-variant results for multiple experiments without changing result semantics" do
    site = create(:site)
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero")
    pricing = create(:section, page:, kind: "pricing", position: 2)
    hero_experiment = create(:experiment, site:, section: hero, primary_goal: "form_submit")
    pricing_experiment = create(:experiment, site:, section: pricing, primary_goal: "any_conversion")
    hero_control = create(:variant, experiment: hero_experiment, key: "control", role: "control")
    hero_variant = create(:variant, experiment: hero_experiment, key: "variant", role: "variant")
    pricing_variant = create(:variant, experiment: pricing_experiment, key: "variant", role: "variant")

    hero_control_assignment = hero_experiment.assignments.create!(visitor_id: "hero-control", variant: hero_control)
    hero_variant_assignment = hero_experiment.assignments.create!(visitor_id: "hero-variant", variant: hero_variant)
    pricing_assignment = pricing_experiment.assignments.create!(visitor_id: "pricing-variant", variant: pricing_variant)
    hero_control_assignment.conversions.create!(event: event_for(site, "hero-control", "form_submit"), conversion_type: "form_submit")
    hero_variant_assignment.conversions.create!(event: event_for(site, "hero-variant", "order_created"), conversion_type: "order_created")
    pricing_assignment.conversions.create!(event: event_for(site, "pricing-variant", "form_submit"), conversion_type: "form_submit")
    pricing_assignment.conversions.create!(event: event_for(site, "pricing-variant", "order_created"), conversion_type: "order_created")

    results = described_class.new([ hero_experiment, pricing_experiment ]).call

    hero_rows = results.fetch(hero_experiment.id)
    pricing_rows = results.fetch(pricing_experiment.id)
    expect(hero_rows.find { |row| row.fetch(:variant) == hero_control }.fetch(:conversions)).to eq(1)
    expect(hero_rows.find { |row| row.fetch(:variant) == hero_variant }.fetch(:conversions)).to eq(0)
    expect(pricing_rows.find { |row| row.fetch(:variant) == pricing_variant }.fetch(:conversions)).to eq(1)
  end

  def event_for(site, visitor_id, event_type)
    site.events.create!(
      event_type:,
      visitor_id:,
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )
  end
end
