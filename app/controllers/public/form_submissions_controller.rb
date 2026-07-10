module Public
  class FormSubmissionsController < BaseController
    InvalidSubmissionPayload = Class.new(StandardError)

    def create
      site = find_site
      form = site.forms.find(params[:form_id])
      # 表单归属的区块如果不在已发布快照里，就不能接收公开提交，避免草稿表单提前收集数据。
      return render plain: "该表单暂不可提交", status: :unprocessable_content unless form.section&.uid && section_uid_visible?(site, form.section.uid)
      request_token = validated_request_token
      return redirect_after_submission(site) if find_submission_by_request_token(form, request_token)

      payload = submission_params(form).to_h
      return render plain: "请填写邮箱", status: :unprocessable_content if payload["email"].blank?
      return render plain: "邮箱格式不正确", status: :unprocessable_content unless payload["email"].match?(URI::MailTo::EMAIL_REGEXP)
      missing_field = form.form_fields.find { |field| field.required? && payload[field.param_key].blank? }
      return render plain: "请填写#{missing_field.label}", status: :unprocessable_content if missing_field

      contact = nil
      event = nil
      ActiveRecord::Base.transaction do
        # 联系人和提交记录一起写入；事件在校验和持久化成功后再记录，避免无效表单进入漏斗。
        contact = site.contacts.find_or_create_by!(email: payload.fetch("email")) do |record|
          record.name = payload["name"]
          record.source = "public_site"
        end
        form.form_submissions.create!(contact:, payload:, request_token:)
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

      redirect_after_submission(site)
    rescue ActiveRecord::RecordNotUnique => error
      raise unless request_token_constraint_violation?(error, FormSubmission::REQUEST_TOKEN_INDEX_NAME)
      raise unless request_token && form && find_submission_by_request_token(form, request_token)

      redirect_after_submission(site)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "提交内容未通过校验，请检查后重试", status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError, InvalidRequestToken, InvalidSubmissionPayload => error
      render plain: error.message, status: :unprocessable_content
    end

    private

    def find_submission_by_request_token(form, request_token)
      return nil unless request_token

      FormSubmission.find_by(form_id: form.id, request_token:)
    end

    def redirect_after_submission(site)
      redirect_to public_site_path(site.slug, submitted: 1)
    end

    def submission_params(form)
      allowed_keys = form.form_fields.map(&:param_key)
      allowed_keys |= %w[email name message]
      # 公开表单是开放输入，缺失或畸形 payload 要走业务校验返回 422，不能冒成框架异常。
      payload = params.key?(:form_submission) ? params[:form_submission] : ActionController::Parameters.new
      case payload
      when ActionController::Parameters
        payload.permit(*allowed_keys)
      when Hash
        ActionController::Parameters.new(payload).permit(*allowed_keys)
      else
        raise InvalidSubmissionPayload, "表单内容格式不正确"
      end
    end
  end
end
