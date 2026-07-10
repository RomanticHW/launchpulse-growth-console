require "digest"

module Events
  class IngestionService
    class InvalidToken < StandardError; end
    class InvalidPayload < StandardError; end

    METADATA_LIMIT_BYTES = 4.kilobytes

    def initialize(params:, request:)
      @params = params
      @request = request
    end

    def call
      api_key = authenticate!
      site = api_key.site
      validate_payload!
      fingerprint = payload_fingerprint
      key = idempotency_key
      event, = resolve_event(site, idempotency_key: key, payload_fingerprint: fingerprint)

      api_key.update!(last_used_at: Time.current)
      Events::AggregationDispatcher.call(event) unless event.aggregated_at?
      event
    end

    private

    def authenticate!
      token = @params.fetch(:site_token)
      raise InvalidToken, "invalid site token" unless token.is_a?(String)

      payload = Rails.application.message_verifier(:site_tracking).verify(token)
      payload = payload.with_indifferent_access
      api_key = ApiKey.active.find_by(site_id: payload.fetch(:site_id), token_digest: ApiKey.digest(payload.fetch(:token)))
      raise InvalidToken, "invalid site token" unless api_key

      api_key
    rescue KeyError, ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken, "invalid site token"
    end

    def validate_payload!
      raise InvalidPayload, "event_type is required" if @params[:event_type].blank?
      raise InvalidPayload, "visitor_id is required" if @params[:visitor_id].blank?
      raise InvalidPayload, "event_type is invalid" unless Event::TYPES.include?(@params[:event_type])

      source = @params[:source].presence || "direct"
      device = @params[:device].presence || "desktop"
      raise InvalidPayload, "source is invalid" unless Event::SOURCES.include?(source)
      raise InvalidPayload, "device is invalid" unless Event::DEVICES.include?(device)
      metadata
    rescue Events::MetadataSanitizer::InvalidMetadata => error
      raise InvalidPayload, error.message
    end

    def find_or_create_event!(site, idempotency_key:, payload_fingerprint:)
      event = site.events.create!(
        page: page_for(site),
        event_type: @params[:event_type],
        visitor_id: @params[:visitor_id],
        session_id: @params[:session_id],
        source: @params[:source].presence || "direct",
        device: @params[:device].presence || "desktop",
        experiment: @attribution&.fetch(:experiment, nil),
        variant: @attribution&.fetch(:variant, nil),
        variant_key: @attribution&.fetch(:variant_key, nil) || @params[:variant_key],
        metadata:,
        payload_fingerprint:,
        idempotency_key:,
        ip_address: @request.remote_ip,
        user_agent: @request.user_agent,
        occurred_at: parsed_time
      )
      [ event, true ]
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      raise if idempotency_key.blank? || !idempotency_conflict?(error)

      existing_idempotent_event(site, idempotency_key, payload_fingerprint) || raise
    end

    def resolve_event(site, idempotency_key:, payload_fingerprint:)
      if idempotency_key.present?
        with_idempotency_lock(site, idempotency_key) do
          resolve_event_inside_transaction(site, idempotency_key:, payload_fingerprint:)
        end
      else
        ActiveRecord::Base.transaction do
          resolve_event_inside_transaction(site, idempotency_key:, payload_fingerprint:)
        end
      end
    end

    def resolve_event_inside_transaction(site, idempotency_key:, payload_fingerprint:)
      if (existing = existing_idempotent_event(site, idempotency_key, payload_fingerprint))
        existing
      else
        # 实验分配和事件在同一事务中创建，避免留下不完整的归因记录。
        attribution_for(site)
        find_or_create_event!(site, idempotency_key:, payload_fingerprint:)
      end
    end

    def with_idempotency_lock(site, idempotency_key)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "SELECT pg_advisory_xact_lock(?)",
            idempotency_lock_key(site, idempotency_key)
          ])
        )
        yield
      end
    end

    def idempotency_lock_key(site, idempotency_key)
      Digest::SHA256.hexdigest("event-idempotency:#{site.id}:#{idempotency_key}").first(15).to_i(16)
    end

    def idempotency_conflict?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)

      error.record&.errors&.of_kind?(:idempotency_key, :taken)
    end

    def idempotency_key
      @params[:idempotency_key].presence
    end

    def payload_fingerprint
      @payload_fingerprint ||= Events::PayloadFingerprint.call(fingerprint_params)
    end

    def existing_idempotent_event(site, idempotency_key, payload_fingerprint)
      return nil if idempotency_key.blank?

      existing = site.events.find_by(idempotency_key:)
      return nil unless existing

      # 幂等键代表业务事件；并发冲突后仍需比较请求指纹。
      raise InvalidPayload, "idempotency key payload fingerprint missing" if existing.payload_fingerprint.blank?
      raise InvalidPayload, "idempotency key payload mismatch" if existing.payload_fingerprint != payload_fingerprint

      [ existing, false ]
    end

    def attribution_for(site)
      @attribution = explicit_attribution(site) || section_attribution(site)
    end

    def explicit_attribution(site)
      return nil if @params[:experiment_id].blank? && @params[:variant_key].blank?
      raise InvalidPayload, "experiment_id is required for explicit variant attribution" if @params[:experiment_id].blank?
      raise InvalidPayload, "variant_key is required for explicit experiment attribution" if @params[:variant_key].blank?

      experiment = site.experiments.active.find_by(id: @params[:experiment_id])
      raise InvalidPayload, "experiment is invalid" unless experiment
      # 显式实验归因仍需校验已发布区块，草稿和已移除区块不能产生实验数据。
      raise InvalidPayload, "experiment section is not published" unless experiment.section&.uid && Sites::PublishedRuntime.new(site).visible_section_uid?(experiment.section.uid)

      variant = experiment.variants.find_by(key: @params[:variant_key])
      raise InvalidPayload, "variant_key is invalid" unless variant

      assignment = assignment_for!(experiment, variant)
      { experiment:, variant:, variant_key: variant.key, assignment: }
    end

    def section_attribution(site)
      section_uid = @params[:section_uid].presence
      return nil unless section_uid
      # 先确认 `section_uid` 存在于最新发布版本，再创建实验分配。
      raise InvalidPayload, "section is not published" unless Sites::PublishedRuntime.new(site).visible_section_uid?(section_uid)

      experiment = site.experiments.accepting_new_assignments.joins(:section).find_by(sections: { uid: section_uid })
      if experiment
        assignment = Experiments::AssignmentService.new(experiment).assign(@params[:visitor_id])
        return { experiment:, variant: assignment.variant, variant_key: assignment.variant.key, assignment: } if assignment
      end

      # Paused/completed: reuse historical assignment only; never mint a new one.
      experiment = site.experiments.open_for_conversion.joins(:section).find_by(sections: { uid: section_uid })
      return nil unless experiment

      assignment = experiment.assignments.find_by(visitor_id: @params[:visitor_id])
      return nil unless assignment

      { experiment:, variant: assignment.variant, variant_key: assignment.variant.key, assignment: }
    end

    def assignment_for!(experiment, variant)
      assignment = Experiments::AssignmentService.new(experiment).assign(@params[:visitor_id], variant:)
      raise InvalidPayload, "experiment is invalid" unless assignment

      assignment
    rescue Experiments::AssignmentService::VariantConflict
      raise InvalidPayload, "assignment conflicts with variant_key"
    end

    def page_for(site)
      site.pages.find_by(path: @params[:page_path].presence || "/")
    end

    def metadata
      raw_metadata = @params.key?(:metadata) ? @params[:metadata] : {}
      @metadata ||= Events::MetadataSanitizer.new(raw_metadata).call
    rescue Events::MetadataSanitizer::InvalidMetadata => error
      raise InvalidPayload, error.message
    end

    def fingerprint_params
      @params.merge(
        source: @params[:source].presence || "direct",
        device: @params[:device].presence || "desktop",
        page_path: @params[:page_path].presence || "/",
        metadata:
      )
    end

    def parsed_time
      return Time.current if @params[:occurred_at].blank?

      Time.zone.parse(@params[:occurred_at].to_s) || Time.current
    rescue TypeError, ArgumentError
      Time.current
    end
  end
end
