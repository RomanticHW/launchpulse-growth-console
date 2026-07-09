module Public
  class EventsController < BaseController
    skip_forgery_protection only: :create

    ALLOWED_DIRECT_EVENT_TYPES = %w[cta_click form_start product_view checkout_click].freeze

    def create
      site = find_site
      event_type = params[:event_type].to_s
      unless Event::TYPES.include?(event_type)
        render json: { error: "事件类型不正确" }, status: :unprocessable_content
        return
      end
      unless ALLOWED_DIRECT_EVENT_TYPES.include?(event_type)
        render json: { error: "该事件不能从公开页面直接上报" }, status: :unprocessable_content
        return
      end
      section_uid = params[:section_uid].presence
      form_id = params[:form_id].presence
      product_key = params[:product_key].presence
      # 带区块标识的交互事件必须确认区块仍在正式页面中，否则外部请求能给草稿实验刷出访客。
      assignment = assignment_for_section_uid(site, section_uid, require_visible: section_uid.present?)
      event = record_public_event!(
        site:,
        page: site.home_page,
        event_type:,
        metadata: metadata_params,
        assignment:,
        section_uid:,
        form_id:,
        product_key:
      )
      render json: { id: event.id, status: "accepted" }, status: :accepted
    rescue ActiveRecord::RecordInvalid => error
      render json: { error: "事件未通过校验" }, status: :unprocessable_content
    rescue HiddenSectionError, Events::MetadataSanitizer::InvalidMetadata => error
      render json: { error: error.message }, status: :unprocessable_content
    end

    private

    def metadata_params
      params.key?(:metadata) ? params[:metadata] : {}
    end
  end
end
