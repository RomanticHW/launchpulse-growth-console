require "rails_helper"

RSpec.describe Experiments::ResultsService do
  it "marks a variant as leading when it has enough visitors and clear lift" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")

    100.times do |index|
      control_assignment = experiment.assignments.create!(visitor_id: "control-#{index}", variant: control)
      variant_assignment = experiment.assignments.create!(visitor_id: "variant-#{index}", variant:)
      control_assignment.conversions.create!(event: event_for(site, "control-#{index}"), conversion_type: "form_submit") if index < 3
      variant_assignment.conversions.create!(event: event_for(site, "variant-#{index}"), conversion_type: "form_submit") if index < 8
    end

    result = described_class.new(experiment).call.find { |row| row[:variant] == variant }

    expect(result[:confidence]).to be >= 70
    expect(result[:label]).to eq("暂时领先")
    expect(result[:absolute_delta_vs_control]).to eq(5.to_d)
    expect(result[:lift_vs_control]).to eq(166.67.to_d)
  end

  it "marks a variant as underperforming when it is clearly worse than control" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")

    100.times do |index|
      control_assignment = experiment.assignments.create!(visitor_id: "control-worse-#{index}", variant: control)
      variant_assignment = experiment.assignments.create!(visitor_id: "variant-worse-#{index}", variant:)
      control_assignment.conversions.create!(event: event_for(site, "control-worse-#{index}"), conversion_type: "form_submit") if index < 12
      variant_assignment.conversions.create!(event: event_for(site, "variant-worse-#{index}"), conversion_type: "form_submit") if index < 4
    end

    result = described_class.new(experiment).call.find { |row| row[:variant] == variant }

    expect(result[:confidence]).to be >= 80
    expect(result[:label]).to eq("表现偏弱")
  end

  it "requires enough traffic before labeling a winner" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")

    10.times do |index|
      experiment.assignments.create!(visitor_id: "small-control-#{index}", variant: control)
      assignment = experiment.assignments.create!(visitor_id: "small-variant-#{index}", variant:)
      assignment.conversions.create!(event: event_for(site, "small-variant-#{index}"), conversion_type: "form_submit")
    end

    result = described_class.new(experiment).call.find { |row| row[:variant] == variant }

    expect(result[:label]).to eq("数据不足")
  end

  it "labels the control row as control" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")

    result = described_class.new(experiment).call.find { |row| row[:variant] == control }

    expect(result[:label]).to eq("原版本")
  end

  it "counts only the primary goal once per assignment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    variant = create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")
    assignment = experiment.assignments.create!(visitor_id: "goal-visitor", variant:)
    assignment.conversions.create!(event: event_for(site, "goal-visitor"), conversion_type: "form_submit")
    assignment.conversions.create!(event: event_for(site, "goal-visitor"), conversion_type: "order_created")

    result = described_class.new(experiment).call.find { |row| row[:variant] == variant }

    expect(result.fetch(:conversions)).to eq(1)
    expect(result.fetch(:conversion_rate)).to eq(100.to_d)
  end

  it "does not report zero lift when control is zero and variant converts" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, primary_goal: "form_submit")
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant", role: "variant")
    60.times { |index| experiment.assignments.create!(visitor_id: "control-zero-#{index}", variant: control) }
    60.times do |index|
      assignment = experiment.assignments.create!(visitor_id: "variant-zero-#{index}", variant:)
      assignment.conversions.create!(event: event_for(site, "variant-zero-#{index}"), conversion_type: "form_submit") if index < 6
    end

    result = described_class.new(experiment).call.find { |row| row[:variant] == variant }

    expect(result.fetch(:conversion_rate)).to eq(10.to_d)
    expect(result.fetch(:lift_vs_control)).to be_nil
    expect(result.fetch(:lift_label)).to eq("从 0 基准起步")
  end

  def event_for(site, visitor_id)
    site.events.create!(
      event_type: "form_submit",
      visitor_id:,
      source: "direct",
      device: "desktop",
      occurred_at: Time.current
    )
  end
end
