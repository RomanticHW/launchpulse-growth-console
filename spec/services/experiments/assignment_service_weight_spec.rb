require "rails_helper"

RSpec.describe Experiments::AssignmentService do
  it "locks the real site row before the experiment row" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "variant")
    lock_queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _id, payload|
      lock_queries << payload[:sql] if payload[:sql].include?("FOR ")
    end

    described_class.new(experiment).assign("lock-order-visitor")

    site_lock_index = lock_queries.index { |sql| sql.include?('FROM "sites"') && sql.include?("FOR KEY SHARE") }
    experiment_lock_index = lock_queries.index { |sql| sql.include?('FROM "experiments"') && sql.include?("FOR UPDATE") }
    expect(site_lock_index).to be < experiment_lock_index
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

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

  it "uses an explicitly requested variant" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "control", role: "control")
    requested = create(:variant, experiment:, key: "requested", role: "variant")

    assignment = described_class.new(experiment).assign("explicit-visitor", variant: requested)

    expect(assignment.variant).to eq(requested)
  end

  it "rejects an explicitly requested variant that conflicts with an existing assignment" do
    experiment = create(:experiment)
    control = create(:variant, experiment:, key: "control", role: "control")
    requested = create(:variant, experiment:, key: "requested", role: "variant")
    experiment.assignments.create!(visitor_id: "conflicting-visitor", variant: control)

    expect do
      described_class.new(experiment).assign("conflicting-visitor", variant: requested)
    end.to raise_error(described_class::VariantConflict)
  end

  it "rejects an explicitly requested variant from another experiment" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "control", role: "control")
    other_experiment = create(:experiment)
    requested = create(:variant, experiment: other_experiment, key: "other", role: "variant")

    expect do
      described_class.new(experiment).assign("cross-experiment-visitor", variant: requested)
    end.to raise_error(described_class::VariantConflict)
  end

  it "does not mask unrelated assignment validation failures during uniqueness recovery" do
    experiment = create(:experiment)
    create(:variant, experiment:, key: "variant")

    expect do
      described_class.new(experiment).assign(nil)
    end.to raise_error(ActiveRecord::RecordInvalid) do |error|
      expect(error.record.errors.of_kind?(:visitor_id, :blank)).to be(true)
    end
  end

  it "recovers an existing assignment from a visitor uniqueness validation race" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:, key: "variant")
    existing = experiment.assignments.create!(visitor_id: "uniqueness-race-visitor", variant:)
    assignments = experiment.assignments
    invalid_assignment = Assignment.new(experiment:, variant:, visitor_id: existing.visitor_id)
    invalid_assignment.validate
    uniqueness_error = ActiveRecord::RecordInvalid.new(invalid_assignment)
    allow(experiment).to receive(:assignments).and_return(assignments)
    allow(assignments).to receive(:find_by)
      .with(visitor_id: existing.visitor_id)
      .and_return(nil, existing)
    allow(assignments).to receive(:create_or_find_by!).and_raise(uniqueness_error)

    assignment = described_class.new(experiment).assign(existing.visitor_id)

    expect(assignment).to eq(existing)
  end

  it "does not recover a uniqueness validation race that also has another validation error" do
    experiment = create(:experiment)
    variant = create(:variant, experiment:, key: "variant")
    existing = experiment.assignments.create!(visitor_id: "mixed-error-visitor", variant:)
    other_experiment = create(:experiment)
    other_variant = create(:variant, experiment: other_experiment, key: "other")
    assignments = experiment.assignments
    invalid_assignment = Assignment.new(experiment:, variant: other_variant, visitor_id: existing.visitor_id)
    invalid_assignment.validate
    validation_error = ActiveRecord::RecordInvalid.new(invalid_assignment)
    allow(experiment).to receive(:assignments).and_return(assignments)
    allow(assignments).to receive(:find_by)
      .with(visitor_id: existing.visitor_id)
      .and_return(nil, existing)
    allow(assignments).to receive(:create_or_find_by!).and_raise(validation_error)

    expect do
      described_class.new(experiment).assign(existing.visitor_id)
    end.to raise_error(validation_error)
  end
end
