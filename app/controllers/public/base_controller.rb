module Public
  class BaseController < ActionController::Base
    HiddenSectionError = Class.new(StandardError)
    allow_browser versions: :modern

    private

    def visitor_id
      existing = cookies.signed[:launch_pulse_visitor_id]
      return existing if existing.present?

      # 实验分流依赖稳定访客标识；签名 Cookie 可防止请求参数伪造分配结果。
      generated = SecureRandom.uuid
      cookies.signed[:launch_pulse_visitor_id] = {
        value: generated,
        expires: 1.year.from_now,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
      generated
    end

    def session_id
      existing = cookies.signed[:launch_pulse_session_id]
      return existing if existing.present?

      generated = SecureRandom.uuid
      cookies.signed[:launch_pulse_session_id] = {
        value: generated,
        expires: 1.year.from_now,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
      generated
    end

    def find_site
      Site.find_by!(slug: params[:slug], status: "published")
    end

    def assignment_map(site, visible_section_uids: nil)
      site.experiments.active.includes(:variants, :section).each_with_object({}) do |experiment, result|
        next unless experiment.section
        # 公开入口只接受最新发布版本中的区块，草稿区块不能产生访客数据。
        next if visible_section_uids && !visible_section_uids.include?(experiment.section.uid)

        assignment = Experiments::AssignmentService.new(experiment).assign(visitor_id)
        result[experiment.section.uid] = assignment
        result[experiment.section_id] = assignment
      end
    end

    def assignment_for_section_uid(site, section_uid, require_visible: false)
      return nil if section_uid.blank?
      raise HiddenSectionError, "Section is not visible" if require_visible && !section_uid_visible?(site, section_uid)

      experiment = site.experiments.accepting_new_assignments.joins(:section).find_by(sections: { uid: section_uid })
      if experiment
        return Experiments::AssignmentService.new(experiment).assign(visitor_id)
      end

      # Late conversion path: paused/completed unresolved experiments keep historical assignment only.
      experiment = site.experiments.open_for_conversion.joins(:section).find_by(sections: { uid: section_uid })
      return nil unless experiment

      experiment.assignments.find_by(visitor_id: visitor_id)
    end

    def section_uid_visible?(site, section_uid)
      visible_section_uids_for(site).include?(section_uid)
    end

    def visible_section_uids_for(site)
      @visible_section_uids_for ||= {}
      @visible_section_uids_for[site.id] ||= published_runtime(site).visible_section_uids
    end

    def published_sections_for(site, page)
      published_runtime(site).published_sections(page)
    end

    def published_runtime(site)
      @published_runtime ||= {}
      @published_runtime[site.id] ||= Sites::PublishedRuntime.new(site)
    end

    def record_public_event!(site:, event_type:, page: nil, metadata: {}, assignment: nil, section_uid: nil, form_id: nil, product_key: nil, enqueue: true)
      # 页面附加字段同样属于开放输入，合并后统一执行元数据清洗。
      raw_metadata = metadata_hash!(metadata)
      raw_metadata["section_uid"] = section_uid.to_s if section_uid.present?
      raw_metadata["form_id"] = form_id if form_id.present?
      raw_metadata["product_key"] = product_key.to_s if product_key.present?
      event_metadata = Events::MetadataSanitizer.new(raw_metadata).call

      event = site.events.create!(
        page:,
        event_type:,
        visitor_id:,
        session_id:,
        source: params[:source].presence_in(Event::SOURCES) || "direct",
        device: params[:device].presence_in(Event::DEVICES) || "desktop",
        experiment: assignment&.experiment,
        variant: assignment&.variant,
        variant_key: assignment&.variant&.key,
        metadata: event_metadata,
        occurred_at: Time.current
      )
      enqueue_public_event!(event) if enqueue
      event
    end

    def enqueue_public_event!(event)
      AggregateEventJob.perform_later(event.id)
    end

    def metadata_hash!(metadata)
      case metadata
      when ActionController::Parameters
        metadata.to_unsafe_h
      when Hash
        metadata.to_h
      else
        raise Events::MetadataSanitizer::InvalidMetadata, "metadata must be an object"
      end
    end
  end
end
