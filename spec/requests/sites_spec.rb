require "rails_helper"

RSpec.describe "Sites" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "rotates demo tracking tokens by deactivating the previous demo token" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    old_key, old_raw_token = ApiKey.issue!(site:, name: "Demo tracking token")
    old_signed_token = old_key.signed_token(old_raw_token)
    create(:page, site:)

    post session_path, params: { email: user.email, password: "password" }
    post site_rotate_tracking_token_path(site)

    expect(response).to redirect_to(site_path(site))
    expect(old_key.reload.active).to be(false)
    expect(site.api_keys.active.where(name: "Demo tracking token").count).to eq(1)
    follow_redirect!
    expect(response.body).to include("令牌仅显示一次")
    signed_token = response.body.match(%r{<textarea[^>]*>(.*?)</textarea>}m)[1]

    post "/api/v1/events", params: {
      site_token: old_signed_token,
      event_type: "page_view",
      visitor_id: "old-token"
    }
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/events", params: {
      site_token: signed_token,
      event_type: "page_view",
      visitor_id: "new-token"
    }
    expect(response).to have_http_status(:accepted)
  end

  it "keeps the old demo token active when issuing the replacement fails" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    old_key, = ApiKey.issue!(site:, name: "Demo tracking token")
    create(:page, site:)
    allow(ApiKey).to receive(:issue!).and_raise(ActiveRecord::RecordInvalid.new(ApiKey.new))

    sign_in(user)

    post site_rotate_tracking_token_path(site)

    expect(response).to have_http_status(:unprocessable_content)
    expect(old_key.reload).to be_active
    expect(site.api_keys.active.where(name: "Demo tracking token")).to contain_exactly(old_key)
  end

  it "rolls back the new key and keeps the old demo token active when signing fails" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    old_key, = ApiKey.issue!(site:, name: "Demo tracking token")
    create(:page, site:)
    allow(ApiKey).to receive(:issue!).and_wrap_original do |original, **arguments|
      key, raw_token = original.call(**arguments)
      allow(key).to receive(:signed_token).and_raise(ActiveSupport::MessageVerifier::InvalidSignature)
      [ key, raw_token ]
    end

    sign_in(user)

    expect do
      post site_rotate_tracking_token_path(site)
    end.to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
    expect(old_key.reload).to be_active
    expect(site.api_keys.active.where(name: "Demo tracking token")).to contain_exactly(old_key)
    expect(site.api_keys.where(name: "Demo tracking token").count).to eq(1)
  end

  it "renders the same themed illustrations inside the live preview frame" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, industry: "Local coffee shop")
    page = create(:page, site:)
    create(:section, page:, kind: "hero", props: { "headline" => "Coffee", "subheadline" => "Fresh cups", "cta" => "Order" })
    create(:section, page:, kind: "feature_grid", position: 1, props: { "headline" => "Visit", "items" => [
      { "title" => "Beans", "body" => "Roasted nearby" },
      { "title" => "Pickup", "body" => "Ready fast" }
    ] })

    sign_in(user)
    get site_path(site)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-preview-target="frame"')
    expect(response.body).to include('data-illustration="coffee-hero"')
    expect(response.body).to include('data-illustration="coffee-feature-0"')
    expect(response.body).to include('data-illustration="coffee-feature-1"')

    preview_cta = Nokogiri::HTML(response.body).at_css('[data-preview-target="frame"] a[href="#contact"]')
    expect(preview_cta).to be_present
    expect(preview_cta["data-controller"]).to be_nil
    expect(preview_cta["data-public-tracking-event-type-value"]).to be_nil
  end

  it "renders a submit-in-progress label for the visitor simulation action" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    create(:page, site:)

    sign_in(user)
    get site_path(site)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-turbo-submits-with="正在生成模拟数据..."')
  end
end
