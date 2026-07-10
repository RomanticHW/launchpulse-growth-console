require "rails_helper"

RSpec.describe Experiments::AssignmentService do
  it "does not return or create assignments after the experiment stops accepting visitors" do
    %w[paused completed].each do |status|
      experiment = create(:experiment)
      variant = create(:variant, experiment:, key: "variant-#{status}")
      existing = experiment.assignments.create!(visitor_id: "existing-#{status}", variant:)
      stale_experiment = Experiment.find(experiment.id)
      Experiment.where(id: experiment.id).update_all(status:, ended_at: Time.current)

      expect(described_class.new(stale_experiment).assign(existing.visitor_id)).to be_nil
      expect(described_class.new(stale_experiment).assign("new-#{status}")).to be_nil
      expect(experiment.assignments.count).to eq(1)
    end
  end

  it "respects deterministic 100/0 variant weights" do
    experiment = create(:experiment)
    control = create(:variant, experiment:, key: "control", role: "control", weight: 100)
    create(:variant, experiment:, key: "variant", role: "variant", weight: 0)

    20.times do |index|
      assignment = described_class.new(experiment).assign("visitor-#{index}")
      expect(assignment.variant).to eq(control)
    end
  end

  it "falls back to a stable equal split when total weight is zero" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "control", role: "control", weight: 0)
    create(:variant, experiment:, key: "variant", role: "variant", weight: 0)

    first = described_class.new(experiment).assign("visitor")
    second = described_class.new(experiment).assign("visitor")

    expect(second.variant).to eq(first.variant)
    expect(experiment.assignments.count).to eq(1)
  end
end
