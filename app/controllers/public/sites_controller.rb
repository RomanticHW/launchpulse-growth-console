module Public
  class SitesController < BaseController
    def show
      @site = find_site
      @page = @site.home_page
      @sections = published_sections_for(@site, @page)
      @forms_by_section_uid = forms_by_section_uid(@site)
      visible_section_uids = @sections.filter_map(&:uid).to_set
      @assignments_by_section_uid = {}
      assigned_variants = {}
      page_view = nil
      unless request.head?
        ActiveRecord::Base.transaction do
          # 公开页只给已发布区块创建分流；页面浏览本身只记录分配结果，不直接归到某一个实验。
          @assignments_by_section_uid = assignment_map(@site, visible_section_uids:)
          assigned_variants = @assignments_by_section_uid.values.uniq.each_with_object({}) do |assignment, result|
            result[assignment.experiment_id.to_s] = assignment.variant.key
          end
          page_view = record_public_event!(
            site: @site,
            page: @page,
            event_type: "page_view",
            metadata: { public_page: true, assigned_variants: },
            enqueue: false
          )
        end
      end
      @demo_debug = demo_debug_enabled? && !request.head?
      @demo_debug_visitor_id = visitor_id if @demo_debug
      @demo_debug_assignments = demo_debug_assignments(@assignments_by_section_uid) if @demo_debug
      unless request.head?
        enqueue_public_event!(page_view)
        # 访客数也是实验指标；公开访问产生分流后刷新一次面板，避免后台必须等转化才看到 visitor 增长。
        Analytics::DashboardBroadcaster.new(@site).broadcast_experiments if assigned_variants.present?
      end
      @submitted = params[:submitted].present?
      @ordered = params[:ordered].present?
      render layout: "public"
    end

    private

    def demo_debug_enabled?
      Rails.env.development? || ENV["DEMO_DEBUG"] == "true"
    end

    def demo_debug_assignments(assignments_by_section_uid)
      assignments_by_section_uid.values.uniq.map do |assignment|
        label = assignment.variant.role == "control" || assignment.variant.key == "control" ? "原版本" : "建议版本"
        "#{assignment.experiment.name}: #{label}"
      end
    end

    def forms_by_section_uid(site)
      site.forms.includes(:section).each_with_object({}) do |form, result|
        next unless form.section

        # 快照里的 section id 可能和当前数据库 id 不一致，表单映射必须优先支持稳定 uid。
        result[form.section.uid] = form
        result[form.section_id] = form
      end
    end
  end
end
