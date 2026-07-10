require "rails_helper"

RSpec.describe TrafficSimulatorJob do
  it "uses the published runtime to decide visible sections" do
    site = create(:site)
    page = create(:page, site:)
    create(:section, page:, kind: "hero")

    expect(Sites::PublishedRuntime).to receive(:new).with(site).and_call_original

    described_class.perform_now(site.id, visitors: 0)
  end

  it "keeps generic page views unattributed and stores assignment metadata" do
    site = create(:site)
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero", position: 0)
    contact = create(:section, page:, kind: "contact_form", position: 1)
    hero_experiment = create(:experiment, site:, section: hero)
    contact_experiment = create(:experiment, site:, section: contact, primary_goal: "form_submit")
    create(:variant, experiment: hero_experiment, key: "hero", name: "Hero")
    create(:variant, experiment: contact_experiment, key: "contact", name: "Contact")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")

    described_class.perform_now(site.id, visitors: 1)

    page_view = site.events.find_by!(event_type: "page_view")
    expect(page_view.experiment_id).to be_nil
    expect(page_view.variant_id).to be_nil
    expect(page_view.variant_key).not_to include(",") if page_view.variant_key.present?
    expect(page_view.metadata.fetch("assigned_variants")).to include(hero_experiment.id.to_s, contact_experiment.id.to_s)
  end

  it "does not assign hidden section experiments" do
    site = create(:site)
    page = create(:page, site:)
    visible = create(:section, page:, kind: "hero", position: 0)
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    hidden = create(:section, page:, kind: "faq", position: 1)
    visible_experiment = create(:experiment, site:, section: visible)
    hidden_experiment = create(:experiment, site:, section: hidden)
    create(:variant, experiment: visible_experiment, key: "visible", name: "Visible")
    create(:variant, experiment: hidden_experiment, key: "hidden", name: "Hidden")

    described_class.perform_now(site.id, visitors: 1)

    expect(visible_experiment.assignments.count).to eq(1)
    expect(hidden_experiment.assignments.count).to eq(0)
  end

  it "omits experiments that close before the simulator assignment is created" do
    site = create(:site)
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero")
    experiment = create(:experiment, site:, section: hero)
    create(:variant, experiment:, key: "variant", name: "Variant")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    allow_any_instance_of(Experiments::AssignmentService).to receive(:assign).and_return(nil)
    allow_any_instance_of(described_class).to receive(:rand).and_return(0.99)

    expect do
      described_class.perform_now(site.id, visitors: 1)
    end.not_to raise_error

    page_view = site.events.find_by!(event_type: "page_view")
    expect(page_view.metadata.fetch("assigned_variants")).to eq({})
    expect(page_view.experiment_id).to be_nil
    expect(experiment.assignments.count).to eq(0)
  end

  it "throttles experiment panel broadcasts during simulations" do
    site = create(:site)
    page = create(:page, site:)
    hero = create(:section, page:, kind: "hero", position: 0)
    experiment = create(:experiment, site:, section: hero)
    create(:variant, experiment:, key: "hero", name: "Hero")
    Sites::SnapshotService.new(site).publish!(user: nil, note: "Spec publish")
    broadcaster = instance_spy(Analytics::DashboardBroadcaster)
    allow(Analytics::DashboardBroadcaster).to receive(:new).with(site).and_return(broadcaster)
    allow_any_instance_of(described_class).to receive(:rand).and_return(0.99)

    described_class.perform_now(site.id, visitors: 50)

    expect(broadcaster).to have_received(:broadcast_experiments).once
  end
end
