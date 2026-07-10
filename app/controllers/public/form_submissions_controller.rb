module Public
  class FormSubmissionsController < BaseController
    InvalidSubmissionPayload = Class.new(StandardError)

    def create
      site = find_site
      form = site.forms.find(params[:form_id])
      # 只有最新发布版本中的表单可以接收公开提交。
      return render plain: "该表单暂时无法提交。", status: :unprocessable_content unless form.section&.uid && section_uid_visible?(site, form.section.uid)
      payload = submission_params(form).to_h
      return render plain: "请填写邮箱。", status: :unprocessable_content if payload["email"].blank?
      return render plain: "请输入有效的邮箱地址。", status: :unprocessable_content unless payload["email"].match?(URI::MailTo::EMAIL_REGEXP)
      missing_field = form.form_fields.find { |field| field.required? && payload[field.param_key].blank? }
      return render plain: "请填写“#{missing_field.label}”。", status: :unprocessable_content if missing_field

      contact = nil
      event = nil
      ActiveRecord::Base.transaction do
        # 联系人、提交记录和事件在同一事务中写入。
        contact = site.contacts.create_or_find_by!(email: payload.fetch("email")) do |record|
          record.name = payload["name"]
          record.source = "public_site"
        end
        form.form_submissions.create!(contact:, payload:)
        section_uid = form.section&.uid
        assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
        event = record_public_event!(
          site:,
          page: site.home_page,
          event_type: "form_submit",
          metadata: { form_id: form.id },
          assignment:,
          section_uid:,
          form_id: form.id,
          enqueue: false
        )
      end
      enqueue_public_event!(event)

      redirect_to public_site_path(site.slug, submitted: 1)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "提交内容有误，请检查后重试。", status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError, InvalidSubmissionPayload => error
      render plain: error.message, status: :unprocessable_content
    end

    private

    def submission_params(form)
      allowed_keys = form.form_fields.map(&:param_key)
      allowed_keys |= %w[email name message]
      # 缺失或格式错误的表单内容返回 422，不暴露框架异常。
      payload = params.key?(:form_submission) ? params[:form_submission] : ActionController::Parameters.new
      case payload
      when ActionController::Parameters
        payload.permit(*allowed_keys)
      when Hash
        ActionController::Parameters.new(payload).permit(*allowed_keys)
      else
        raise InvalidSubmissionPayload, "表单内容格式不正确。"
      end
    end
  end
end
