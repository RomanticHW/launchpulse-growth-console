require "rails_helper"

RSpec.describe "Authorization" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  def setup_site(role:)
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:, role:)
    site = create(:site, account:)
    [ user, site ]
  end

  it "allows owners to publish" do
    user, site = setup_site(role: Membership::OWNER)
    create(:page, site:)
    sign_in(user)

    post site_publishing_path(site)

    expect(response).to redirect_to(site_path(site))
    expect(flash[:notice]).to match(/已发布/)
  end

  it "blocks viewers from publishing" do
    user, site = setup_site(role: Membership::VIEWER)
    create(:page, site:)
    sign_in(user)

    post site_publishing_path(site)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to match(/没有权限/)
    expect(site.published_snapshots.count).to eq(0)
  end

  it "blocks marketers from running traffic simulation" do
    user, site = setup_site(role: Membership::MARKETER)
    sign_in(user)

    post site_simulation_path(site)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to match(/没有权限/)
  end

  it "blocks marketers from rotating tracking tokens" do
    user, site = setup_site(role: Membership::MARKETER)
    sign_in(user)

    post site_rotate_tracking_token_path(site)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to match(/没有权限/)
  end

  it "does not allow user A to publish user B site by id" do
    account_a = create(:account)
    account_b = create(:account)
    user_a = create(:user, password: "password")
    create(:membership, account: account_a, user: user_a, role: Membership::OWNER)
    site_b = create(:site, account: account_b)
    create(:page, site: site_b)
    sign_in(user_a)

    post site_publishing_path(site_b)

    expect(response).to have_http_status(:not_found)
    expect(site_b.published_snapshots.count).to eq(0)
  end
end
