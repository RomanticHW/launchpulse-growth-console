require "rails_helper"

RSpec.describe Experiments::LifecycleService do
  def recommendation_for(status:)
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8,
      status:,
      suggested_patch: { "cta" => "Get plan" }
    )
    patch_status = status == "applied" ? "applied" : "pending"
    recommendation.create_section_patch!(
      section:,
      status: patch_status,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    [ site, recommendation ]
  end

  def recommendation_for_section(site, section, title:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title:,
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8,
      suggested_patch: { "cta" => title }
    )
    recommendation.create_section_patch!(
      section:,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    recommendation
  end

  it "rejects direct launch from tested and superseded recommendations" do
    %w[tested superseded testing dismissed].each do |status|
      site, recommendation = recommendation_for(status:)

      expect do
        described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
      end.to raise_error(Experiments::LifecycleService::InvalidTransition)
    end
  end

  it "allows applied patch retest only before a winner has been applied" do
    site, recommendation = recommendation_for(status: "applied")
    service = described_class.new

    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    variant = experiment.variants.find_by!(role: "variant")
    service.complete!(experiment:, user: nil, account: site.account)
    service.apply_winner!(experiment:, variant:, user: nil, account: site.account)

    expect do
      service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition)
  end

  it "rejects a second unresolved experiment on the same section" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    first = recommendation_for_section(site, section, title: "First CTA")
    second = recommendation_for_section(site, section, title: "Second CTA")
    service = described_class.new

    service.launch_from_recommendation!(site:, recommendation: first, user: nil, account: site.account)

    expect do
      service.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition, /这个区块已有未结束的实验/)
  end

  it "locks the section while checking and launching an experiment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    recommendation = recommendation_for_section(site, section, title: "Locked CTA")

    expect(section).to receive(:with_lock).and_call_original

    experiment = described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)

    expect(experiment.section).to eq(section)
  end

  it "treats paused and completed-without-winner experiments as unresolved section tests" do
    %w[paused completed].each do |status|
      site = create(:site)
      page = create(:page, site:)
      section = create(:section, page:)
      first = recommendation_for_section(site, section, title: "First CTA #{status}")
      second = recommendation_for_section(site, section, title: "Second CTA #{status}")
      experiment = create(:experiment, site:, section:, recommendation: first, status:, winner_applied_at: nil)

      expect do
        described_class.new.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)
      end.to raise_error(Experiments::LifecycleService::InvalidTransition)
      expect(experiment.reload.winner_applied_at).to be_nil
    end
  end

  it "allows a new section experiment after the previous winner has been applied" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    first = recommendation_for_section(site, section, title: "First CTA")
    second = recommendation_for_section(site, section, title: "Second CTA")
    old_experiment = create(:experiment, site:, section:, recommendation: first, status: "completed", winner_applied_at: Time.current)

    new_experiment = described_class.new.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)

    expect(new_experiment.section).to eq(section)
    expect(old_experiment.reload.winner_applied_at).to be_present
  end
end
