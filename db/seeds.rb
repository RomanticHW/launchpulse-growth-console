puts "正在重置演示数据..."

Account.destroy_all
User.destroy_all

account = Account.create!(name: "LaunchPulse 演示账号", plan: "demo")
user = User.create!(name: "演示负责人", email: "demo@launchpulse.test", password: "password")
Membership.create!(account:, user:, role: "owner")

def build_site(account:, user:, name:, slug:, industry:, score:, sections:, products: [])
  site = account.sites.create!(name:, slug:, industry:, growth_score: score, status: "published")
  page = site.pages.create!(title: "首页", path: "/", position: 0)

  sections.each_with_index do |section, index|
    created_section = page.sections.create!(
      kind: section.fetch(:kind),
      name: section.fetch(:name),
      position: index,
      props: section.fetch(:props)
    )

    if created_section.kind == "contact_form"
      form = site.forms.create!(section: created_section, name: "#{created_section.name}表单")
      fields = section.fetch(:form_fields, [
        { label: "邮箱", key: "email", field_type: "email", required: true },
        { label: "姓名", key: "name", field_type: "text", required: false }
      ])
      fields.each_with_index do |field, field_index|
        form.form_fields.create!(
          label: field.fetch(:label),
          key: field.fetch(:key, field.fetch(:label).to_s.parameterize.underscore),
          field_type: field.fetch(:field_type, "text"),
          metadata: field.fetch(:metadata, {}),
          required: field.fetch(:required, false),
          position: field_index
        )
      end
    end
  end

  products.each do |product|
    site.products.create!(product)
  end

  key, raw_token = ApiKey.issue!(site:)
  Sites::SnapshotService.new(site).publish!(user:, note: "初始发布")
  [ site, key.signed_token(raw_token) ]
end

coffee, coffee_token = build_site(
  account:,
  user:,
  name: "街角晨光咖啡",
  slug: "neighborhood-coffee",
  industry: "本地咖啡店",
  score: 76,
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "早晨出门前，先带上一杯现做咖啡", subheadline: "提前下单，到店即取。每天都有附近烘焙的小批次豆子和当季风味。", cta: "提前点单", eyebrow: "每日营业" } },
    { kind: "feature_grid", name: "到店理由", props: { headline: "熟客愿意一再回来", items: [ { title: "本地烘焙豆", body: "小批次烘焙，风味清楚，适合每天喝。" }, { title: "到店即取", body: "手机下单后，咖啡会放在前台取餐区。" }, { title: "安静长桌", body: "适合简短会面，也适合带电脑坐一会儿。" } ] } },
    { kind: "testimonial", name: "顾客评价", props: { quote: "附近最省心的咖啡店。早高峰不用排太久，季节拿铁也总有惊喜。", author: "Maya，每周都会来" } },
    {
      kind: "contact_form",
      name: "团队订购表单",
      props: { headline: "给团队安排一轮咖啡", helper: "留下日期、人数和取餐时间，我们会确认可供应的饮品。", submit_label: "提交需求" },
      form_fields: [
        { label: "邮箱", key: "email", field_type: "email", required: true },
        { label: "姓名", key: "name", field_type: "text", required: false },
        { label: "需求说明", key: "message", field_type: "textarea", required: true },
        { label: "人数", key: "headcount", field_type: "text", required: true }
      ]
    },
    { kind: "faq", name: "常见问题", props: { headline: "来之前可以先了解", items: [ { question: "可以提前点单吗？", answer: "可以，大部分饮品都支持提前下单，到店取走。" }, { question: "能做团队咖啡吗？", answer: "可以，通过表单留下人数和时间，我们会确认供应安排。" } ] } }
  ]
)

course, course_token = build_site(
  account:,
  user:,
  name: "创作者上新营",
  slug: "studio-sprint-course",
  industry: "线上课程转化页",
  score: 71,
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "用 21 天把数字产品推到市场", subheadline: "给创作者准备的一套上新流程：不用大团队，也能把定位、页面和发布节奏跑顺。", cta: "加入下一期", eyebrow: "新一期即将开营" } },
    { kind: "feature_grid", name: "课程内容", props: { headline: "把上新拆成能执行的步骤", items: [ { title: "产品提案", body: "确定人群、承诺和交付边界，先把产品讲清楚。" }, { title: "销售页", body: "围绕购买顾虑组织内容，让页面更像一次完整沟通。" }, { title: "发布节奏", body: "安排邮件、社媒和合作渠道，不靠临时冲刺。" } ] } },
    { kind: "pricing", name: "价格方案", props: { headline: "按你现在的节奏选择", plans: [ { name: "自学版", plan_key: "self-paced", price: "$149", description: "课程视频、模板和发布清单。" }, { name: "共学版", plan_key: "cohort", price: "$399", description: "直播答疑、作业点评和同伴反馈。" }, { name: "团队版", plan_key: "team", price: "$799", description: "共享工作区和小组辅导。" } ] } },
    {
      kind: "contact_form",
      name: "资料领取表单",
      props: { headline: "领取课程大纲", helper: "留下邮箱，我们会发送课程安排和下一期开营时间。", submit_label: "发送大纲" },
      form_fields: [
        { label: "邮箱", key: "email", field_type: "email", required: true },
        { label: "姓名", key: "name", field_type: "text", required: false },
        { label: "想完成的产品", key: "goal", field_type: "textarea", required: true }
      ]
    }
  ]
)

skincare, skincare_token = build_site(
  account:,
  user:,
  name: "清叶护肤",
  slug: "clearleaf-skincare",
  industry: "小型电商护肤品牌",
  score: 79,
  products: [
    { name: "屏障修护精华", key: "barrier-repair-serum", description: "清爽的日用精华。", price: 34, image_url: "" },
    { name: "舒缓面霜", key: "calm-cream", description: "无香型保湿面霜。", price: 28, image_url: "" },
    { name: "矿物洁面乳", key: "mineral-cleanser", description: "温和的晨间洁面。", price: 22, image_url: "" }
  ],
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "敏感肌护理，不需要复杂选择", subheadline: "三件温和基础款，帮你把日常护理稳定下来。", cta: "查看套组", eyebrow: "通过皮肤测试" } },
    { kind: "product_grid", name: "产品套组", props: { headline: "每天都用得上的三步", products: [ { name: "屏障修护精华", product_key: "barrier-repair-serum", price: "$34" }, { name: "舒缓面霜", product_key: "calm-cream", price: "$28" }, { name: "矿物洁面乳", product_key: "mineral-cleanser", price: "$22" } ] } },
    { kind: "testimonial", name: "用户反馈", props: { quote: "终于不用每天换来换去，皮肤状态也慢慢稳定了。", author: "真实购买用户" } },
    { kind: "faq", name: "常见问题", props: { headline: "护理前可以先了解", items: [ { question: "有香精吗？", answer: "核心套组为无香型配方。" }, { question: "可以每天使用吗？", answer: "这三件产品都按日常使用设计。" } ] } }
  ]
)

def seed_events(site, visitors:)
  sources = Event::SOURCES
  devices = Event::DEVICES
  page = site.home_page

  visitors.times do |index|
    visitor_id = "#{site.slug}-seed-#{index}"
    source = sources.sample
    device = devices.sample
    occurred_at = rand(14.days.to_i).seconds.ago
    site.events.create!(page:, event_type: "page_view", visitor_id:, session_id: "seed-#{index}", source:, device:, occurred_at:)

    next unless rand < 0.38

    site.events.create!(page:, event_type: "cta_click", visitor_id:, session_id: "seed-#{index}", source:, device:, occurred_at: occurred_at + rand(90).seconds)

    next unless rand < 0.18

    conversion_type = site.products.exists? ? "order_created" : "form_submit"
    site.events.create!(page:, event_type: conversion_type, visitor_id:, session_id: "seed-#{index}", source:, device:, occurred_at: occurred_at + rand(240).seconds)
  end
end

seed_events(coffee, visitors: 180)
seed_events(course, visitors: 220)
seed_events(skincare, visitors: 260)

puts "已生成 #{Account.count} 个账号、#{User.count} 个用户、#{Site.count} 个站点、#{Event.count} 条事件。"
puts "演示登录：demo@launchpulse.test / password"
puts "咖啡站点签名 token：#{coffee_token}"
puts "课程站点签名 token：#{course_token}"
puts "护肤站点签名 token：#{skincare_token}"
