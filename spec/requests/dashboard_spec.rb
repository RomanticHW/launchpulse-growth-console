require "rails_helper"

RSpec.describe "Dashboard" do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password" }
  end

  it "renders growth gauges from an empty ring state for client animation" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    create(:site, account:, name: "仪表盘测试页", growth_score: 82)

    sign_in(user)
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-gauge-score-value="82"')
    expect(response.body).to include('stroke-dashoffset="100"')
    expect(response.body).not_to include('stroke-dashoffset="18"')
  end

  it "renders per-site area sparklines from summary trend data" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "趋势测试页")
    page = create(:page, site:)
    site.events.create!(page:, event_type: "page_view", visitor_id: "visitor-a", source: "direct", device: "desktop", occurred_at: 1.day.ago)
    site.events.create!(page:, event_type: "order_created", visitor_id: "visitor-a", source: "direct", device: "desktop", occurred_at: 1.day.ago + 5.minutes)

    sign_in(user)
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-sparkline-trend')
    expect(response.body).to include("<path")
    expect(response.body).not_to include('points="0,13 12,10 24,12 36,6 48,8 60,4 72,7"')
    expect(response.body).to include("趋势测试页")
  end

  it "renders a mobile navigation drawer for authenticated users" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)
    create(:site, account:, name: "移动导航测试页")

    sign_in(user)
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('aria-controls="mobile_navigation_drawer"')
    expect(response.body).to include('id="mobile_navigation_drawer"')
    expect(response.body).to include("移动导航测试页")
    expect(response.body).to include("退出登录")
  end

  it "renders a useful empty state when the account has no sites" do
    account = create(:account)
    user = create(:user, password: "password")
    create(:membership, account:, user:)

    sign_in(user)
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("还没有站点")
    expect(response.body).to include("接入站点后，这里会显示页面表现、转化趋势和实验状态。")
  end

  it "redirects authenticated users without an account away from protected pages" do
    user = create(:user, password: "password")

    sign_in(user)
    get root_path

    expect(response).to redirect_to(new_session_path)
  end
end
