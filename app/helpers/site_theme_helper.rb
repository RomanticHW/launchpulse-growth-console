module SiteThemeHelper
  SITE_THEMES = {
    coffee: {
      match: /coffee|cafe|咖啡|咖啡店/i,
      base: "#2B1D16",
      surface: "#3A2A1E",
      ink: "#F5ECE1",
      accent: "#E8A33D",
      accent_2: "#7FA37A",
      on_accent: "#2B1D16",
      display_weight: 500,
      display_tracking: "-0.01em",
      display_transform: "none",
      display_leading: 1.2
    },
    course: {
      match: /course|sprint|training|cohort|课程|训练营|营/i,
      base: "#0E0B1A",
      surface: "#181329",
      ink: "#F1EEFB",
      accent: "#FF5A36",
      accent_2: "#4C8DFF",
      on_accent: "#0E0B1A",
      display_weight: 800,
      display_tracking: "0.02em",
      display_transform: "uppercase",
      display_leading: 1.08
    },
    skincare: {
      match: /skincare|beauty|cosmetic|护肤|美妆|个护/i,
      base: "#F4F7F1",
      surface: "#FFFFFF",
      ink: "#1D2A20",
      accent: "#6B8F71",
      accent_2: "#E7B7A8",
      on_accent: "#0B1220",
      display_weight: 350,
      display_tracking: "0.045em",
      display_transform: "none",
      display_leading: 1.28
    }
  }.freeze

  DEFAULT_THEME = {
    base: "#F7F5F0",
    surface: "#FFFFFF",
    ink: "#10182B",
    accent: "#8B7CF6",
    accent_2: "#F5A524",
    on_accent: "#FFFFFF",
    display_weight: 650,
    display_tracking: "-0.01em",
    display_transform: "none",
    display_leading: 1.16
  }.freeze

  SECTION_KIND_COLORS = {
    "hero" => "bg-signal-amber",
    "feature_grid" => "bg-signal-violet",
    "pricing" => "bg-emerald-500",
    "testimonial" => "bg-sky-500",
    "product_grid" => "bg-signal-violet",
    "contact_form" => "bg-signal-amber"
  }.freeze

  EVENT_TYPE_COLORS = {
    "page_view" => "bg-slate-400",
    "form_start" => "bg-signal-violet",
    "form_submit" => "bg-signal-violet",
    "cta_click" => "bg-signal-amber",
    "checkout_click" => "bg-signal-amber",
    "order_created" => "bg-signal-amber"
  }.freeze

  SECTION_KIND_LABELS = {
    "hero" => "首屏",
    "feature_grid" => "卖点",
    "pricing" => "价格",
    "testimonial" => "评价",
    "product_grid" => "产品",
    "contact_form" => "表单",
    "faq" => "问答"
  }.freeze

  EVENT_TYPE_LABELS = {
    "page_view" => "浏览页面",
    "form_start" => "开始填写",
    "form_submit" => "提交表单",
    "cta_click" => "点击按钮",
    "checkout_click" => "点击结账",
    "order_created" => "创建订单"
  }.freeze

  FUNNEL_STEP_LABELS = {
    "form_submit_or_order" => "提交或下单"
  }.freeze

  SOURCE_LABELS = {
    "direct" => "直接访问",
    "search" => "搜索",
    "social" => "社媒",
    "referral" => "推荐",
    "email" => "邮件",
    "paid" => "付费推广"
  }.freeze

  DEVICE_LABELS = {
    "desktop" => "桌面",
    "mobile" => "手机",
    "tablet" => "平板"
  }.freeze

  STATUS_LABELS = {
    "open" => "待处理",
    "pending" => "待处理",
    "testing" => "测试中",
    "tested" => "已测试",
    "active" => "运行中",
    "paused" => "已暂停",
    "completed" => "已完成",
    "applied" => "已应用",
    "dismissed" => "已忽略",
    "superseded" => "已替换",
    "reverted" => "已回滚"
  }.freeze

  PRODUCT_ICON_KEYWORDS = {
    "serum" => "serum",
    "精华" => "serum",
    "cream" => "cream",
    "面霜" => "cream",
    "乳霜" => "cream",
    "cleanser" => "cleanser",
    "洁面" => "cleanser",
    "洗面" => "cleanser",
    "wash" => "cleanser",
    "moisturizer" => "cream",
    "moisturiser" => "cream",
    "乳液" => "cream",
    "toner" => "bottle",
    "lotion" => "cream",
    "balm" => "cream",
    "oil" => "serum"
  }.freeze

  def site_theme_key_for(site)
    SITE_THEMES.find { |_key, theme| theme[:match].match?(site&.industry.to_s) }&.first || :default
  end

  def site_theme_for(site)
    SITE_THEMES.fetch(site_theme_key_for(site), DEFAULT_THEME)
  end

  def site_theme_style(site)
    theme = site_theme_for(site)
    <<~CSS.squish
      --site-base: #{theme[:base]};
      --site-surface: #{theme[:surface]};
      --site-ink: #{theme[:ink]};
      --site-accent: #{theme[:accent]};
      --site-accent-2: #{theme[:accent_2]};
      --site-on-accent: #{theme[:on_accent]};
      --site-display-weight: #{theme[:display_weight]};
      --site-display-tracking: #{theme[:display_tracking]};
      --site-display-transform: #{theme[:display_transform]};
      --site-display-leading: #{theme[:display_leading]};
    CSS
  end

  def site_hero_illustration(site)
    illustration_partial_for(site, "hero", "shared/illustrations/default_hero")
  end

  def site_feature_icon(site, _index)
    illustration_partial_for(site, "feature_icon", "shared/illustrations/default_icon")
  end

  def site_product_icon(site)
    illustration_partial_for(site, "product_icon", "shared/illustrations/default_icon")
  end

  def site_testimonial_illustration(site)
    illustration_partial_for(site, "testimonial", "shared/illustrations/default_icon")
  end

  def product_icon_variant(product_name)
    normalized_name = product_name.to_s.downcase
    PRODUCT_ICON_KEYWORDS.find { |keyword, _variant| normalized_name.include?(keyword) }&.last || "bottle"
  end

  def section_kind_color(kind)
    SECTION_KIND_COLORS.fetch(kind.to_s, "bg-slate-400")
  end

  def event_type_color(event_type)
    EVENT_TYPE_COLORS.fetch(event_type.to_s, "bg-slate-400")
  end

  def section_kind_label(kind)
    SECTION_KIND_LABELS.fetch(kind.to_s, kind.to_s)
  end

  def event_type_label(event_type)
    EVENT_TYPE_LABELS.fetch(event_type.to_s, event_type.to_s)
  end

  def funnel_step_label(step)
    FUNNEL_STEP_LABELS.fetch(step.to_s) { event_type_label(step) }
  end

  def source_label(source)
    SOURCE_LABELS.fetch(source.to_s, source.to_s)
  end

  def device_label(device)
    DEVICE_LABELS.fetch(device.to_s, device.to_s)
  end

  def status_label(status)
    STATUS_LABELS.fetch(status.to_s, status.to_s)
  end

  def relative_time_label(time)
    seconds = (Time.current - time).abs
    return "刚刚" if seconds < 60
    return "#{(seconds / 60).floor} 分钟前" if seconds < 1.hour
    return "#{(seconds / 1.hour).floor} 小时前" if seconds < 1.day

    "#{(seconds / 1.day).floor} 天前"
  end

  private

  def illustration_partial_for(site, suffix, fallback)
    partial = "shared/illustrations/#{site_theme_key_for(site)}_#{suffix}"
    lookup_context.exists?(partial, [], true) ? partial : fallback
  end
end
