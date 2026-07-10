module Public
  class SitesController < BaseController
    def show
      @site = find_site
      @page = @site.home_page
      @sections = published_sections_for(@site, @page)
      @forms_by_section_uid = forms_by_section_uid(@site)
      visible_section_uids = @sections.filter_map(&:uid).to_set
      # 只为已发布区块创建分配；页面浏览记录分配结果，但不归入单个实验。
      @assignments_by_section_uid = request.head? ? {} : assignment_map(@site, visible_section_uids:)
      @demo_debug = demo_debug_enabled? && !request.head?
      @demo_debug_visitor_id = visitor_id if @demo_debug
      @demo_debug_assignments = demo_debug_assignments(@assignments_by_section_uid) if @demo_debug
      unless request.head?
        assigned_variants = @assignments_by_section_uid.values.uniq.each_with_object({}) do |assignment, result|
          result[assignment.experiment_id.to_s] = assignment.variant.key
        end
        record_public_event!(site: @site, page: @page, event_type: "page_view", metadata: { public_page: true, assigned_variants: })
        # 新分配产生后立即刷新实验面板，使访客数及时更新。
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
        label = assignment.variant.role == "control" || assignment.variant.key == "control" ? "原始版本" : "优化版本"
        "#{assignment.experiment.name}: #{label}"
      end
    end

    def forms_by_section_uid(site)
      site.forms.includes(:section).each_with_object({}) do |form, result|
        next unless form.section

        # 历史版本中的区块编号可能变化，表单映射优先使用稳定 `uid`。
        result[form.section.uid] = form
        result[form.section_id] = form
      end
    end
  end
end
