require "rails_helper"

RSpec.describe "Publishing" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "renders a readable HTML diff and keeps JSON available" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    section = create(:section, page:, name: "Hero", props: { "headline" => "Before" })
    snapshot = Sites::SnapshotService.new(site).publish!(user:, note: "Before")
    section.update!(props: { "headline" => "After" })

    sign_in(user)
    get diff_site_publishing_path(site, snapshot_id: snapshot.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hero")
    expect(response.body).to include("headline")
    expect(response.body).to include("修改前")
    expect(response.body).to include("修改后")
    expect(response.body).to include('data-diff-value-panel="before"')
    expect(response.body).not_to include("&quot;Before&quot;")

    get diff_site_publishing_path(site, snapshot_id: snapshot.id, format: :json)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("changed_sections").first.fetch("changed_keys")).to include("headline")
  end

  it "renders long changed values in structured HTML panels while keeping full raw JSON" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    long_before = "Before " * 80
    long_after = "After " * 80
    section = create(:section, page:, name: "Hero", props: { "headline" => long_before })
    snapshot = Sites::SnapshotService.new(site).publish!(user:, note: "Before")
    section.update!(props: { "headline" => long_after })

    sign_in(user)
    get diff_site_publishing_path(site, snapshot_id: snapshot.id)

    expect(response.body).to include(long_before)
    expect(response.body).to include(long_after)
    expect(response.body).to include('data-diff-value-panel="after"')
    expect(response.body).to include("max-h-72 overflow-y-auto")

    get diff_site_publishing_path(site, snapshot_id: snapshot.id, format: :json)

    expect(response.body).to include(long_after)
  end

  it "renders empty states for added and removed sections" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    create(:section, page:, name: "Hero", props: { "headline" => "Same" })
    snapshot = Sites::SnapshotService.new(site).publish!(user:, note: "Before")

    sign_in(user)
    get diff_site_publishing_path(site, snapshot_id: snapshot.id)

    expect(response.body).to include("没有新增区块。")
    expect(response.body).to include("没有删除区块。")
  end

  it "reports added and removed sections in diff output" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    removed = create(:section, page:, name: "Old FAQ", kind: "faq", props: { "headline" => "Old" })
    snapshot = Sites::SnapshotService.new(site).publish!(user:, note: "Before")
    removed.destroy!
    create(:section, page:, name: "New Hero", kind: "hero", props: { "headline" => "New" })

    sign_in(user)
    get diff_site_publishing_path(site, snapshot_id: snapshot.id)

    expect(response.body).to include("Old FAQ")
    expect(response.body).to include("New Hero")
  end

  it "redirects with an alert when rollback checksum fails" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:)
    page = create(:page, site:)
    create(:section, page:)
    snapshot = Sites::SnapshotService.new(site).publish!(user:, note: "Before")
    snapshot.update_column(:checksum, "tampered")

    sign_in(user)
    post rollback_site_publishing_path(site, snapshot_id: snapshot.id)

    expect(response).to redirect_to(site_path(site))
    expect(flash[:alert]).to match(/checksum/i)
  end
end
