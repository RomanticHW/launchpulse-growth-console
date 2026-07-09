require "rails_helper"

RSpec.describe "Experiments" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "launches an experiment from immutable patch props after the patch is applied" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original", "cta" => "Start" })
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      suggested_patch: { "headline" => "Recommended", "cta" => "Get plan" }
    )
    patch = recommendation.create_section_patch!(
      section:,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    patch.apply!

    sign_in(user)
    post site_experiments_path(site, recommendation_id: recommendation.id)

    experiment = site.experiments.last
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    expect(experiment.variants.find_by!(role: "control").props).to eq("headline" => "Original", "cta" => "Start")
    expect(experiment.variants.find_by!(role: "variant").props).to eq("headline" => "Recommended", "cta" => "Get plan")
  end

  it "does not create duplicate active experiments for the same recommendation" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      suggested_patch: { "cta" => "Get plan" }
    )
    recommendation.create_section_patch!(
      section:,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )

    sign_in(user)
    2.times { post site_experiments_path(site, recommendation_id: recommendation.id) }

    expect(site.experiments.where(recommendation:, status: "active").count).to eq(1)
  end

  it "rejects dismissed recommendations" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      status: "dismissed",
      suggested_patch: { "cta" => "Get plan" }
    )

    sign_in(user)
    post site_experiments_path(site, recommendation_id: recommendation.id)

    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    expect(site.experiments.count).to eq(0)
  end

  it "pauses, resumes, completes, and applies a winning variant" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original" })
    experiment = create(:experiment, site:, section:, status: "active")
    variant = create(:variant, experiment:, key: "variant", name: "Recommended", props: { "headline" => "Winner" })

    sign_in(user)
    post pause_site_experiment_path(site, experiment)
    expect(experiment.reload.status).to eq("paused")
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))

    post resume_site_experiment_path(site, experiment)
    expect(experiment.reload.status).to eq("active")
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))

    post complete_site_experiment_path(site, experiment)
    expect(experiment.reload.status).to eq("completed")
    expect(experiment.ended_at).to be_present
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))

    post apply_winner_site_experiment_path(site, experiment, variant_id: variant.id)
    expect(section.reload.props).to eq("headline" => "Winner")
    expect(AuditLog.where(site:, action: "experiment_winner_applied")).to exist
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
  end

  it "does not apply a winner before completion" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original" })
    experiment = create(:experiment, site:, section:, status: "active")
    variant = create(:variant, experiment:, key: "variant", name: "Recommended", props: { "headline" => "Winner" })

    sign_in(user)
    post apply_winner_site_experiment_path(site, experiment, variant_id: variant.id)

    expect(section.reload.props).to eq("headline" => "Original")
  end

  it "rejects invalid lifecycle transitions after completion" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    experiment = create(:experiment, site:, section:, status: "completed", ended_at: Time.current)

    sign_in(user)
    post pause_site_experiment_path(site, experiment)
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    expect(experiment.reload.status).to eq("completed")

    post resume_site_experiment_path(site, experiment)
    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    expect(experiment.reload.status).to eq("completed")
  end

  it "blocks duplicate unresolved experiments for a recommendation" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      status: "tested",
      suggested_patch: { "cta" => "Get plan" }
    )
    recommendation.create_section_patch!(
      section:,
      status: "tested",
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    create(:experiment, site:, section:, recommendation:, status: "completed", ended_at: Time.current)

    sign_in(user)
    post site_experiments_path(site, recommendation_id: recommendation.id)

    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    expect(site.experiments.where(recommendation:).count).to eq(1)
  end

  it "applies recommended winner without mutating immutable patch snapshots" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Original" })
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      status: "tested",
      suggested_patch: { "headline" => "Recommended" }
    )
    patch = recommendation.create_section_patch!(
      section:,
      status: "tested",
      props_diff: recommendation.suggested_patch,
      before_props: { "headline" => "Original" },
      after_props: { "headline" => "Recommended" }
    )
    experiment = create(:experiment, site:, section:, recommendation:, status: "completed", ended_at: Time.current)
    variant = create(:variant, experiment:, key: "variant", name: "Recommended", role: "variant", props: { "headline" => "Winner" })

    sign_in(user)
    post apply_winner_site_experiment_path(site, experiment, variant_id: variant.id)

    expect(section.reload.props).to eq("headline" => "Winner")
    expect(recommendation.reload.status).to eq("applied")
    expect(patch.reload.status).to eq("applied")
    expect(patch.before_props).to eq("headline" => "Original")
    expect(patch.after_props).to eq("headline" => "Recommended")
  end

  it "marks control winner as superseded instead of applied" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, props: { "headline" => "Current" })
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8% clicks",
      confidence: 0.8,
      status: "tested",
      suggested_patch: { "headline" => "Recommended" }
    )
    patch = recommendation.create_section_patch!(
      section:,
      status: "tested",
      props_diff: recommendation.suggested_patch,
      before_props: { "headline" => "Original" },
      after_props: { "headline" => "Recommended" }
    )
    experiment = create(:experiment, site:, section:, recommendation:, status: "completed", ended_at: Time.current)
    control = create(:variant, experiment:, key: "control", name: "Control", role: "control", props: { "headline" => "Original" })

    sign_in(user)
    post apply_winner_site_experiment_path(site, experiment, variant_id: control.id)

    expect(section.reload.props).to eq("headline" => "Original")
    expect(recommendation.reload.status).to eq("superseded")
    expect(patch.reload.status).to eq("superseded")
    expect(patch.applied).to be(false)
  end
end
