require "rails_helper"

RSpec.describe Experiments::AssignmentService do
  it "assigns the same visitor to the same variant deterministically" do
    experiment = create(:experiment)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control")
    variant = create(:variant, experiment:, key: "variant", name: "Variant")

    first = described_class.new(experiment).assign("visitor-123")
    second = described_class.new(experiment).assign("visitor-123")

    expect(second.id).to eq(first.id)
    expect([ control.id, variant.id ]).to include(first.variant_id)
    expect(experiment.assignments.count).to eq(1)
  end

  it "handles duplicate assignment attempts without creating duplicates" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "control", name: "Control", role: "control")
    create(:variant, experiment:, key: "variant", name: "Variant")
    service = described_class.new(experiment)

    first = service.assign("visitor-456")
    allow(experiment.assignments).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    duplicate = service.assign("visitor-456")

    expect(duplicate.id).to eq(first.id)
    expect(experiment.assignments.count).to eq(1)
  end
end
