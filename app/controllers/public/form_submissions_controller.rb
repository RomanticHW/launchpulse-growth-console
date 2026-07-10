module Public
  class FormSubmissionsController < BaseController
    InvalidSubmissionPayload = Class.new(StandardError)

    def create
      site = find_site
      form = site.forms.find(params[:form_id])
      request_token = validated_request_token
      payload = submission_params(form).to_h
      section_uid = params[:section_uid].presence || form.section&.uid
      request_fingerprint = form_request_fingerprint(form, section_uid, payload, request_token)
      submission = resolve_form_submission(
        site:,
        form:,
        payload:,
        section_uid:,
        request_token:,
        request_fingerprint:
      )
      enqueue_pending_submission_events!(site, submission)

      redirect_after_submission(site)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "提交内容未通过校验，请检查后重试", status: :unprocessable_content
    rescue RequestFingerprintMismatch => error
      render plain: error.message, status: :conflict
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError, InvalidRequestToken, InvalidSubmissionPayload => error
      render plain: error.message, status: :unprocessable_content
    end

    private

    def resolve_form_submission(site:, form:, payload:, section_uid:, request_token:, request_fingerprint:)
      operation = proc do
        existing = find_submission_by_request_token(form, request_token)
        if existing
          ensure_matching_request_fingerprint!(existing, request_fingerprint)
        else
          create_form_submission!(
            site:,
            form:,
            payload:,
            section_uid:,
            request_token:,
            request_fingerprint:
          )
        end
      end

      if request_token
        PublicRequests::IdempotencyLock.with_lock(
          scope: "form:#{form.id}",
          request_token:,
          &operation
        )
      else
        ActiveRecord::Base.transaction(&operation)
      end
    rescue ActiveRecord::RecordNotUnique => error
      raise unless request_token_constraint_violation?(error, FormSubmission::REQUEST_TOKEN_INDEX_NAME)

      recover_form_submission!(form, request_token, request_fingerprint, error)
    rescue ActiveRecord::RecordInvalid => error
      raise unless form_request_token_taken?(error)

      recover_form_submission!(form, request_token, request_fingerprint, error)
    end

    def create_form_submission!(site:, form:, payload:, section_uid:, request_token:, request_fingerprint:)
      validate_form_submission!(site, form, section_uid, payload)
      contact = create_or_find_contact!(site, payload)
      submission = form.form_submissions.create!(
        contact:,
        payload:,
        request_token:,
        request_fingerprint:
      )
      assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
      record_public_event!(
        site:,
        page: site.home_page,
        event_type: "form_submit",
        metadata: { form_id: form.id, form_submission_id: submission.id },
        assignment:,
        section_uid:,
        form_id: form.id,
        enqueue: false
      )
      submission
    end

    def validate_form_submission!(site, form, section_uid, payload)
      unless form.section&.uid && form.section.uid == section_uid && section_uid_visible?(site, section_uid)
        raise InvalidSubmissionPayload, "该表单暂不可提交"
      end
      raise InvalidSubmissionPayload, "请填写邮箱" if payload["email"].blank?
      raise InvalidSubmissionPayload, "邮箱格式不正确" unless payload["email"].match?(URI::MailTo::EMAIL_REGEXP)

      missing_field = form.form_fields.find { |field| field.required? && payload[field.param_key].blank? }
      raise InvalidSubmissionPayload, "请填写#{missing_field.label}" if missing_field
    end

    def create_or_find_contact!(site, payload)
      site.contacts.create_or_find_by!(email: payload.fetch("email")) do |record|
        record.name = payload["name"]
        record.source = "public_site"
      end
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record.is_a?(Contact) && error.record.errors.of_kind?(:email, :taken)

      site.contacts.find_by!(email: payload.fetch("email"))
    end

    def recover_form_submission!(form, request_token, request_fingerprint, original_error)
      existing = find_submission_by_request_token(form, request_token)
      raise original_error unless existing

      ensure_matching_request_fingerprint!(existing, request_fingerprint)
    end

    def form_request_token_taken?(error)
      error.record.is_a?(FormSubmission) && error.record.errors.of_kind?(:request_token, :taken)
    end

    def form_request_fingerprint(form, section_uid, payload, request_token)
      return nil unless request_token

      PublicRequests::Fingerprint.call(
        operation: "form_submission",
        attributes: { form_id: form.id, section_uid:, payload: }
      )
    end

    def enqueue_pending_submission_events!(site, submission)
      site.events
        .where(event_type: "form_submit", aggregated_at: nil)
        .where("metadata @> ?", { form_submission_id: submission.id }.to_json)
        .find_each { |event| enqueue_public_event!(event) }
    end

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
