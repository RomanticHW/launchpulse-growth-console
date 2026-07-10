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
end
