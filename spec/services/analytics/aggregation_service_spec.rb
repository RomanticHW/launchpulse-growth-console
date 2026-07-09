require "rails_helper"

RSpec.describe Analytics::AggregationService do
  it "increments rollups only once per event" do
    site = create(:site)
    event = site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-1",
      source: "search",
      device: "mobile",
      occurred_at: Time.current
    )

    described_class.new(event).call
    described_class.new(event.reload).call

    expect(site.event_rollups.find_by!(metric: "event:page_view", dimension: "all").count).to eq(1)
    expect(event.reload.aggregated_at).to be_present
  end

  it "records conversion for an assigned visitor" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(assignment.conversions.where(event:).count).to eq(1)
  end

  it "creates one conversion per assignment for duplicate aggregation attempts" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    2.times { described_class.new(event.reload).call }

    expect(assignment.conversions.where(conversion_type: "form_submit").count).to eq(1)
  end

  it "does not overwrite an event's explicit experiment attribution when multiple experiments convert" do
    site = create(:site)
    page = create(:page, site:)
    first_section = create(:section, page:)
    second_section = create(:section, page:, position: 1)
    first_experiment = create(:experiment, site:, section: first_section)
    second_experiment = create(:experiment, site:, section: second_section)
    first_variant = create(:variant, experiment: first_experiment, key: "first", name: "First")
    second_variant = create(:variant, experiment: second_experiment, key: "second", name: "Second")
    first_experiment.assignments.create!(visitor_id: "visitor-1", variant: first_variant)
    second_experiment.assignments.create!(visitor_id: "visitor-1", variant: second_variant)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      experiment: first_experiment,
      variant: first_variant,
      variant_key: first_variant.key,
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(event.reload.experiment).to eq(first_experiment)
    expect(event.variant).to eq(first_variant)
    expect(Conversion.count).to eq(1)
    expect(first_experiment.conversions.count).to eq(1)
    expect(second_experiment.conversions.count).to eq(0)
  end

  it "does not create a conversion when explicit event variant conflicts with existing assignment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", role: "control", name: "Control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-1", variant: control)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      experiment:,
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.aggregated_at).to be_present
  end

  it "does not create a conversion when assignment creation races into a variant mismatch" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", role: "control", name: "Control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    assignment = experiment.assignments.create!(visitor_id: "visitor-race", variant: control)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-race",
      source: "direct",
      device: "desktop",
      experiment:,
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )
    assignments = experiment.assignments
    allow(experiment).to receive(:assignments).and_return(assignments)
    allow(event).to receive(:experiment).and_return(experiment)
    allow(assignments).to receive(:find_by).with(visitor_id: "visitor-race").and_return(nil)
    allow(assignments).to receive(:create_or_find_by!).and_raise(ActiveRecord::RecordNotUnique)
    allow(assignments).to receive(:find_by!).with(visitor_id: "visitor-race").and_return(assignment)

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.aggregated_at).to be_present
  end

  it "attributes section-specific conversions only to the matching section experiment" do
    site = create(:site)
    page = create(:page, site:)
    product_section = create(:section, page:, kind: "product_grid", position: 0)
    pricing_section = create(:section, page:, kind: "pricing", position: 1)
    product_experiment = create(:experiment, site:, section: product_section, primary_goal: "order_created")
    pricing_experiment = create(:experiment, site:, section: pricing_section, primary_goal: "order_created")
    product_variant = create(:variant, experiment: product_experiment, key: "product", name: "Product")
    pricing_variant = create(:variant, experiment: pricing_experiment, key: "pricing", name: "Pricing")
    product_experiment.assignments.create!(visitor_id: "visitor-1", variant: product_variant)
    pricing_experiment.assignments.create!(visitor_id: "visitor-1", variant: pricing_variant)
    event = site.events.create!(
      event_type: "order_created",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      metadata: { section_uid: product_section.uid },
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(product_experiment.conversions.count).to eq(1)
    expect(pricing_experiment.conversions.count).to eq(0)
    expect(event.reload.experiment).to eq(product_experiment)
  end

  it "does not infer assignment for section-specific conversion events" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    create(:variant, experiment:, key: "variant", name: "Variant")
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-without-exposure",
      source: "direct",
      device: "desktop",
      metadata: { section_uid: section.uid },
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.assignments.count).to eq(0)
    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.experiment_id).to be_nil
  end

  it "creates an assignment for explicit attributed conversion events" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-explicit-exposure",
      source: "direct",
      device: "desktop",
      experiment:,
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )

    described_class.new(event).call

    assignment = experiment.assignments.find_by!(visitor_id: "visitor-explicit-exposure")
    expect(assignment.variant).to eq(variant)
    expect(assignment.conversions.where(event:).count).to eq(1)
  end

  it "does not fall back to generic attribution when only experiment is present" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-partial-experiment", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-partial-experiment",
      source: "direct",
      device: "desktop",
      experiment:,
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.aggregated_at).to be_present
  end

  it "does not fall back to generic attribution when only variant is present" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-partial-variant", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-partial-variant",
      source: "direct",
      device: "desktop",
      variant:,
      variant_key: variant.key,
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.aggregated_at).to be_present
  end

  it "does not assign generic conversions to the first experiment" do
    site = create(:site)
    page = create(:page, site:)
    first_section = create(:section, page:, position: 0)
    second_section = create(:section, page:, position: 1)
    first_experiment = create(:experiment, site:, section: first_section, primary_goal: "order_created")
    second_experiment = create(:experiment, site:, section: second_section, primary_goal: "order_created")
    first_variant = create(:variant, experiment: first_experiment, key: "first", name: "First")
    second_variant = create(:variant, experiment: second_experiment, key: "second", name: "Second")
    first_experiment.assignments.create!(visitor_id: "visitor-1", variant: first_variant)
    second_experiment.assignments.create!(visitor_id: "visitor-1", variant: second_variant)
    event = site.events.create!(
      event_type: "order_created",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(first_experiment.conversions.count).to eq(1)
    expect(second_experiment.conversions.count).to eq(1)
    expect(event.reload.experiment_id).to be_nil
    expect(event.variant_id).to be_nil
  end

  it "does not create generic order conversions for form-submit experiments" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = site.events.create!(
      event_type: "order_created",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.experiment_id).to be_nil
  end

  it "does not create generic form conversions for order-created experiments" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "order_created")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-1", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.experiment_id).to be_nil
  end

  it "creates generic conversions only for matching goals and any-conversion goals" do
    site = create(:site)
    page = create(:page, site:)
    order_section = create(:section, page:, position: 0)
    any_section = create(:section, page:, position: 1)
    ignored_section = create(:section, page:, position: 2)
    order_experiment = create(:experiment, site:, section: order_section, primary_goal: "order_created")
    any_experiment = create(:experiment, site:, section: any_section, primary_goal: "any_conversion")
    ignored_experiment = create(:experiment, site:, section: ignored_section, primary_goal: "form_submit")
    order_variant = create(:variant, experiment: order_experiment, key: "order", name: "Order")
    any_variant = create(:variant, experiment: any_experiment, key: "any", name: "Any")
    ignored_variant = create(:variant, experiment: ignored_experiment, key: "ignored", name: "Ignored")
    order_experiment.assignments.create!(visitor_id: "visitor-1", variant: order_variant)
    any_experiment.assignments.create!(visitor_id: "visitor-1", variant: any_variant)
    ignored_experiment.assignments.create!(visitor_id: "visitor-1", variant: ignored_variant)
    event = site.events.create!(
      event_type: "order_created",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(order_experiment.conversions.count).to eq(1)
    expect(any_experiment.conversions.count).to eq(1)
    expect(ignored_experiment.conversions.count).to eq(0)
    expect(event.reload.experiment_id).to be_nil
  end

  it "handles legacy non-object metadata without crashing" do
    site = create(:site)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-legacy-metadata",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )
    event.update_column(:metadata, [ "legacy", "array" ])

    expect { described_class.new(event.reload).call }.not_to raise_error
    expect(event.reload.aggregated_at).to be_present
  end

  it "does not fall back to generic attribution when section uid has no active experiment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")
    experiment.assignments.create!(visitor_id: "visitor-missing-section", variant:)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-missing-section",
      source: "direct",
      device: "desktop",
      metadata: { section_uid: "missing-section" },
      occurred_at: Time.current
    )

    described_class.new(event).call

    expect(experiment.conversions.count).to eq(0)
    expect(event.reload.experiment_id).to be_nil
  end

  it "broadcasts the experiments panel after conversion events" do
    site = create(:site)
    event = site.events.create!(
      event_type: "form_submit",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    broadcaster = instance_spy(Analytics::DashboardBroadcaster)
    allow(Analytics::DashboardBroadcaster).to receive(:new).with(site).and_return(broadcaster)

    described_class.new(event).call

    expect(broadcaster).to have_received(:broadcast_event).with(event)
    expect(broadcaster).to have_received(:broadcast_summary)
    expect(broadcaster).to have_received(:broadcast_experiments)
  end

  it "does not broadcast the experiments panel for non-conversion events" do
    site = create(:site)
    event = site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-1",
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )

    broadcaster = instance_spy(Analytics::DashboardBroadcaster)
    allow(Analytics::DashboardBroadcaster).to receive(:new).with(site).and_return(broadcaster)

    described_class.new(event).call

    expect(broadcaster).to have_received(:broadcast_event).with(event)
    expect(broadcaster).to have_received(:broadcast_summary)
    expect(broadcaster).not_to have_received(:broadcast_experiments)
  end
end
