require "rails_helper"

RSpec.describe "Section patches" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "redirects with alert instead of raising for invalid testing patch actions" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak headline", severity: "medium")
    recommendation = site.recommendations.create!(ai_finding: finding, section:, title: "Improve", problem: "Weak", expected_impact: "More clicks", confidence: 0.8)
    patch = recommendation.create_section_patch!(section:, props_diff: { "headline" => "Better" }, status: "testing")

    sign_in(user)
    post apply_site_section_patch_path(site, patch)

    expect(response).to redirect_to(site_path(site, selected_section_id: section.id))
    follow_redirect!
    expect(response.body).to include("cannot be applied")
  end

  it "keeps the patched section selected when previewing a change" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak headline", severity: "medium")
    recommendation = site.recommendations.create!(ai_finding: finding, section:, title: "Improve", problem: "Weak", expected_impact: "More clicks", confidence: 0.8)
    patch = recommendation.create_section_patch!(section:, props_diff: { "headline" => "Better" })

    sign_in(user)
    get preview_site_section_patch_path(site, patch)

    expect(response).to redirect_to(site_path(site, preview_recommendation_id: recommendation.id, selected_section_id: section.id))
  end
end
