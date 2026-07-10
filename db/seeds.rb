puts "正在重置示例数据..."

Account.destroy_all
User.destroy_all

account = Account.create!(name: "LaunchPulse 示例账号", plan: "demo")
user = User.create!(name: "站点负责人", email: "demo@launchpulse.test", password: "password")
Membership.create!(account:, user:, role: Membership::OWNER)

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
  name: "巷口咖啡",
  slug: "neighborhood-coffee",
  industry: "社区咖啡店",
  score: 76,
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "上班路上，顺手带走一杯刚做好的咖啡", subheadline: "线上提前点单，到店直接取餐。每日供应经典咖啡、当季特调和现烤点心。", cta: "立即点单", eyebrow: "07:30—20:00 营业" } },
    { kind: "feature_grid", name: "门店特色", props: { headline: "好喝、省时，也适合坐一会儿", items: [ { title: "每周新鲜烘焙", body: "咖啡豆每周新鲜烘焙，提供手冲、意式咖啡和当季特调。" }, { title: "提前点单取餐", body: "手机下单后按约定时间到店，直接在取餐区领取。" }, { title: "门店座位充足", body: "设有长桌和电源，适合短暂办公或朋友见面。" } ] } },
    { kind: "testimonial", name: "顾客留言", props: { quote: "早上提前点好，到店基本不用等。咖啡口味稳定，店里也很安静。", author: "顾客反馈示例" } },
    {
      kind: "contact_form",
      name: "团队订购表单",
      props: { headline: "会议和活动用咖啡，可提前预订", helper: "请填写日期、人数和取餐时间，门店确认后会与你联系。", submit_label: "提交预订" },
      form_fields: [
        { label: "邮箱", key: "email", field_type: "email", required: true },
        { label: "姓名", key: "name", field_type: "text", required: false },
        { label: "需求说明", key: "message", field_type: "textarea", required: true },
        { label: "人数", key: "headcount", field_type: "text", required: true }
      ]
    },
    { kind: "faq", name: "常见问题", props: { headline: "到店前常见问题", items: [ { question: "可以提前点单吗？", answer: "可以。大部分饮品支持线上下单，到店后直接取餐。" }, { question: "可以预订会议或活动用咖啡吗？", answer: "可以。请通过预订表单提交人数和时间，门店会确认饮品与取餐安排。" } ] } }
  ]
)

course, course_token = build_site(
  account:,
  user:,
  name: "创作者产品上线课",
  slug: "studio-sprint-course",
  industry: "在线实战课程",
  score: 71,
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "21 天完成数字产品从定位到上线", subheadline: "适合第一次做课程、模板或会员产品的创作者。跟着课程完成定位、销售页和上线计划。", cta: "查看课程安排", eyebrow: "第 6 期招募中" } },
    { kind: "feature_grid", name: "课程内容", props: { headline: "每周都有明确的学习任务", items: [ { title: "确定产品定位", body: "梳理目标用户、核心问题和交付内容，形成清楚的产品说明。" }, { title: "完成销售页面", body: "按用户决策顺序组织页面内容，逐项回应常见购买疑问。" }, { title: "制定上线计划", body: "安排预热、发布和复盘节点，明确每个阶段要完成的工作。" } ] } },
    { kind: "pricing", name: "价格方案", props: { headline: "选择适合你的学习方式", plans: [ { name: "自学版", plan_key: "self-paced", price: "¥999", description: "录播课程、配套模板和上线清单。" }, { name: "共学版", plan_key: "cohort", price: "¥2,699", description: "包含直播答疑、作业点评和小组交流。" }, { name: "团队版", plan_key: "team", price: "¥5,999", description: "支持 5 人学习，包含两次团队辅导。" } ] } },
    {
      kind: "contact_form",
      name: "资料领取表单",
      props: { headline: "领取完整课程大纲", helper: "填写邮箱后，我们会发送课程安排、学习方式和近期上课时间。", submit_label: "获取课程大纲" },
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
  industry: "基础护肤品牌",
  score: 79,
  products: [
    { name: "屏障修护精华", key: "barrier-repair-serum", description: "水润质地，适合日常保湿使用。", price: 239, image_url: "" },
    { name: "舒缓面霜", key: "calm-cream", description: "无香型乳霜质地，适合早晚基础保湿。", price: 199, image_url: "" },
    { name: "矿物洁面乳", key: "mineral-cleanser", description: "低泡型洁面，适合晨间和晚间清洁。", price: 159, image_url: "" }
  ],
  sections: [
    { kind: "hero", name: "首屏", props: { headline: "三步基础护理，早晚都容易坚持", subheadline: "洁面、精华和面霜组成一套简单的日常护理，不用反复搭配。", cta: "查看基础套装", eyebrow: "日常基础护理" } },
    { kind: "product_grid", name: "产品套装", props: { headline: "从清洁到保湿，三步完成", products: [ { name: "屏障修护精华", product_key: "barrier-repair-serum", price: "¥239" }, { name: "舒缓面霜", product_key: "calm-cream", price: "¥199" }, { name: "矿物洁面乳", product_key: "mineral-cleanser", price: "¥159" } ] } },
    { kind: "testimonial", name: "使用反馈", props: { quote: "步骤不多，早晚照着用就行。每件产品的用法和用量也写得很清楚。", author: "用户反馈示例" } },
    { kind: "faq", name: "常见问题", props: { headline: "购买前常见问题", items: [ { question: "产品是否添加香精？", answer: "基础套装中的三件产品均为无香型。" }, { question: "可以每天使用吗？", answer: "产品按日常清洁和保湿场景设计，具体使用频率可根据个人肤况调整。" } ] } }
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
puts "体验账号：demo@launchpulse.test / password"
puts "咖啡站点追踪令牌：#{coffee_token}"
puts "课程站点追踪令牌：#{course_token}"
puts "护肤站点追踪令牌：#{skincare_token}"
