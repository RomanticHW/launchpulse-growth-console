require "rails_helper"

RSpec.describe "Audit and experiment flow", type: :system do
  it "creates an audit and launches an experiment from a recommendation" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "课程发布页")
    page_record = create(:page, site:)
    create(:section, page: page_record, kind: "hero", name: "首屏")
    create(:section, page: page_record, kind: "contact_form", name: "线索表单", position: 1, props: { "headline" => "领取发布清单", "submit_label" => "提交" })

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "课程发布页"

    click_button "分析页面", match: :first
    expect(page).to have_content("页面分析完成")
    expect(page).to have_content("明确首屏按钮的操作结果")
    expect(page).to have_css('[data-turbo-submits-with="正在应用..."]', text: "应用到草稿")

    click_link "预览改动", match: :first
    expect(page).to have_content("查看详细方案")
    selected_section_id = Rack::Utils.parse_query(URI.parse(current_url).query)["selected_section_id"]
    expect(selected_section_id).to be_present
    expect(page).to have_css(%([data-controller~="inspector"][data-inspector-section-id-value="#{selected_section_id}"]))
    expect(page).to have_css(%([data-controller~="inspector"][data-inspector-preview-section-id-value="#{selected_section_id}"]))

    click_button "应用到草稿", match: :first
    expect(page).to have_content("改动已应用到草稿")
    expect(page).to have_css(%([data-controller~="inspector"][data-inspector-section-id-value="#{selected_section_id}"]))
    expect(page).to have_content("查看详细方案")
    expect(page).to have_css('[data-turbo-submits-with="正在撤回..."]', text: "撤回")
    expect(page).to have_css('[data-turbo-submits-with="正在创建..."]', text: "创建对照实验")

    click_button "创建对照实验", match: :first
    expect(page).to have_content("实验已启动")
    expect(page).to have_content("实验")
    expect(page).to have_content("原始版本")
    expect(page).to have_content("优化版本")

    experiment = site.experiments.last
    expect(experiment.variants.find_by!(role: "control").props).not_to eq(experiment.variants.find_by!(role: "variant").props)
  end

  it "shows a focused preview workspace with section inspector controls" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "咖啡测试页")
    page_record = create(:page, site:)
    create(:section, page: page_record, kind: "hero", name: "首屏")
    create(:section, page: page_record, kind: "contact_form", name: "线索表单", position: 1, props: { "headline" => "预约咨询", "submit_label" => "提交" })

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "咖啡测试页"

    expect(page).to have_content("站点概览")
    expect(page).to have_content("增长分数")
    expect(page).to have_content("页面浏览")
    expect(page).to have_content("发布版本")
    expect(page).to have_button("页面结构与版本")
    expect(page).to have_css('[data-inspector-target~="sidebar"]')
    expect(page).to have_css('[data-controller~="preview"][data-preview-default-mode-value="auto"][data-preview-mobile-breakpoint-value="640"]')
    expect(page).to have_css('[data-turbo-submits-with="正在分析..."]', text: "分析页面")
    expect(page).to have_css('[data-turbo-submits-with="正在发布..."]', text: "发布")
    expect(page).to have_css('details summary', text: "测试工具")
    expect(page).to have_css('details [data-turbo-submits-with="正在生成..."]', text: "生成追踪令牌", visible: :all)
    expect(page).to have_css('[data-turbo-submits-with="正在生成模拟数据..."]', text: "模拟 1000 位访客", visible: :all)
    expect(page).to have_css(%([data-count-up-key-value="site-#{site.id}-status-page-views"]))
    expect(page).to have_css(%([data-count-up-key-value="site-#{site.id}-summary-page-views"]))
    expect(page).to have_css(%([data-count-up-key-value="site-#{site.id}-summary-conversion-rate"]))
    expect(page).to have_css('button[aria-pressed="true"]', text: "桌面")
    expect(page).to have_css('button[aria-pressed="false"]', text: "手机")
    expect(page).to have_css('[data-preview-target~="viewport"]')
    expect(page).to have_css('[data-preview-target~="sizer"]')
    expect(page).to have_css('[data-preview-target~="frame"]')
    expect(page).to have_css('[data-controller~="event-stream"][data-event-stream-limit-value="25"][data-event-stream-quiet-threshold-value="5"]')
    expect(page).to have_no_button("查看首屏")
    expect(page).to have_css(%([data-inspector-target="section"][data-action*="inspector#selectSection"][data-section-name="首屏"][role="group"][aria-label="首屏 区块预览"]))
    expect(page).to have_css(%([data-inspector-target="section"][role="group"] button[aria-label="查看 首屏 区块"]), visible: :all)
    expect(page).to have_no_css('[data-inspector-target="section"][role="button"]', visible: :all)
    expect(page).to have_content("2 个区块")
  end

  it "marks preview hotspots and exposes drawer and inspector focus hooks" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "精品测试页")
    page_record = create(:page, site:)
    hero = create(:section, page: page_record, kind: "hero", name: "首屏")
    form_section = create(:section, page: page_record, kind: "contact_form", name: "线索表单", position: 1, props: { "headline" => "预约咨询", "submit_label" => "提交" })
    recommendation = create_recommendation_for(site:, section: hero)
    create_active_experiment_for(site:, section: hero, recommendation:)
    create_paused_experiment_for(site:, section: form_section)
    create_completed_experiment_for(site:, section: form_section)

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "精品测试页"

    expect(page).to have_button("页面结构与版本")
    expect(page).to have_css('[data-drawer-target="panel"][role="dialog"][aria-modal="true"][data-action*="keydown->drawer#trapFocus"]', visible: :hidden)
    expect(page).to have_css(%([data-action~="inspector#selectCard"][data-section-id="#{hero.id}"]))
    expect(page).to have_css(%([data-hotspot-section-id="#{hero.id}"]), text: "建议")
    expect(page).to have_css(%([data-hotspot-section-id="#{hero.id}"]), text: "实验中")
    expect(page).to have_css("[data-change-before]", text: "Grow faster")
    expect(page).to have_css("[data-change-after]", text: "预约页面优化咨询")
    expect(page).to have_css(%([role="progressbar"][aria-label="优化建议置信度"][aria-valuenow="86"][aria-valuemin="0"][aria-valuemax="100"]))
    expect(page).to have_css('[role="progressbar"] .progress-bar-fill')
    expect(page).to have_css('[data-turbo-submits-with="正在暂停..."]', text: "暂停")
    expect(page).to have_css('[data-turbo-submits-with="正在继续..."]', text: "继续实验")
    expect(page).to have_css('[data-turbo-submits-with="正在结束..."]', text: "结束实验")
    expect(page).to have_content("实验结果已应用")
  end

  it "prioritizes the leading variant when a completed experiment needs a decision" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "实验决策页")
    page_record = create(:page, site:)
    section = create(:section, page: page_record, kind: "contact_form", name: "线索表单", props: { "headline" => "预约咨询", "submit_label" => "提交" })
    create_decision_experiment_for(site:, section:)

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "实验决策页"

    expect(page).to have_xpath("//button[normalize-space()='采用 优化版本' and contains(@class,'bg-emerald-600') and contains(@class,'text-white')]")
    expect(page).to have_xpath("//button[normalize-space()='采用 原始版本' and contains(@class,'bg-white') and contains(@class,'text-slate-600')]")
    expect(page).to have_css('[data-turbo-submits-with="正在应用..."]', text: "采用 优化版本")
    expect(page).to have_css('[data-turbo-submits-with="正在应用..."]', text: "采用 原始版本")
    expect(page).to have_css('[data-experiment-progress-bar][aria-hidden="true"]')
    expect(page).to have_no_css("[data-experiment-progress-bar] span")
  end

  it "marks global empty states as overview-only content" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "空状态测试页")
    page_record = create(:page, site:)
    create(:section, page: page_record, kind: "hero", name: "首屏")

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "空状态测试页"

    expect(page).to have_content("分析页面后，这里会显示可预览和应用的优化建议。")
    expect(page).to have_content("可从优化建议直接创建对照实验。")
    expect(page).to have_css('[data-inspector-target~="overview"]', text: "分析页面后，这里会显示可预览和应用的优化建议。")
    expect(page).to have_css('[data-inspector-target~="overview"] [data-turbo-submits-with="正在分析..."]', text: "分析页面")
    expect(page).to have_css('[data-inspector-target~="overview"]', text: "可从优化建议直接创建对照实验。")
  end

  it "binds Escape to clear the selected section" do
    account = create(:account)
    user = create(:user, email: "owner@example.test", password: "password")
    create(:membership, account:, user:)
    site = create(:site, account:, name: "键盘退出测试页")
    page_record = create(:page, site:)
    create(:section, page: page_record, kind: "hero", name: "首屏")

    visit new_session_path
    fill_in "邮箱", with: "owner@example.test"
    fill_in "密码", with: "password"
    click_button "进入控制台"
    click_link "键盘退出测试页"

    expect(page).to have_css('[data-controller~="inspector"][data-action*="keydown.esc@window->inspector#clear"]')
  end

  def create_recommendation_for(site:, section:)
    audit = AiAudit.create!(site:, status: "completed", score: 81, summary: "首屏按钮需要说明操作结果。")
    finding = AiFinding.create!(ai_audit: audit, section:, problem: "按钮文案过于笼统。", severity: "high")
    recommendation = Recommendation.create!(
      site:,
      ai_finding: finding,
      section:,
      title: "明确首屏按钮的操作结果",
      problem: "访客点击前难以判断下一步内容。",
      expected_impact: "重点观察表单提交率",
      confidence: 0.86,
      suggested_patch: { "headline" => "预约页面优化咨询" }
    )
    SectionPatch.create!(
      recommendation:,
      section:,
      props_diff: { "headline" => "预约页面优化咨询" },
      before_props: section.props,
      after_props: section.props.merge("headline" => "预约页面优化咨询")
    )
    recommendation
  end

  def create_active_experiment_for(site:, section:, recommendation:)
    experiment = create(:experiment, site:, section:, recommendation:, name: "首屏行动测试", status: "active")
    create(:variant, experiment:, key: "control", name: "原始版本", role: "control", weight: 50)
    create(:variant, experiment:, key: "variant", name: "优化版本", role: "variant", weight: 50)
    experiment
  end

  def create_completed_experiment_for(site:, section:)
    experiment = create(:experiment, site:, section:, name: "表单承诺测试", status: "completed", ended_at: Time.current)
    create(:variant, experiment:, key: "control", name: "原始版本", role: "control", weight: 50)
    winner = create(:variant, experiment:, key: "variant", name: "优化版本", role: "variant", weight: 50)
    experiment.update!(winner_variant: winner, winner_applied_at: Time.current)
    experiment
  end

  def create_paused_experiment_for(site:, section:)
    experiment = create(:experiment, site:, section:, name: "表单暂停测试", status: "paused")
    create(:variant, experiment:, key: "control", name: "原始版本", role: "control", weight: 50)
    create(:variant, experiment:, key: "variant", name: "优化版本", role: "variant", weight: 50)
    experiment
  end

  def create_decision_experiment_for(site:, section:)
    experiment = create(:experiment, site:, section:, name: "表单决策测试", status: "completed", ended_at: Time.current)
    control = create(:variant, experiment:, key: "control", name: "原始版本", role: "control", weight: 50)
    variant = create(:variant, experiment:, key: "variant", name: "优化版本", role: "variant", weight: 50)
    seed_variant_results(experiment:, variant: control, visitors: 80, conversions: 8)
    seed_variant_results(experiment:, variant:, visitors: 80, conversions: 18)
    experiment
  end

  def seed_variant_results(experiment:, variant:, visitors:, conversions:)
    visitors.times do |index|
      assignment = Assignment.create!(experiment:, variant:, visitor_id: "#{variant.key}-visitor-#{index}")
      Conversion.create!(assignment:, conversion_type: "form_submit") if index < conversions
    end
  end
end
