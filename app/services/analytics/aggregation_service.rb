module Analytics
  class AggregationService
    CONVERSION_EVENTS = Conversion::EVENT_TYPES

    def initialize(event)
      @event = event
      @site = event.site
    end

    def call
      return if @event.aggregated_at?

      ActiveRecord::Base.transaction do
        # 先锁定事件并检查聚合时间，确保重复任务不会重复写入统计和转化。
        @event.lock!
        return if @event.aggregated_at?

        increment_rollup!("event:#{@event.event_type}", "all")
        increment_rollup!("source", @event.source)
        increment_rollup!("device", @event.device)
        if @event.event_type == "page_view"
          increment_rollup!("page_view_source", @event.source)
          increment_rollup!("page_view_device", @event.device)
        end
        record_experiment_conversion! if CONVERSION_EVENTS.include?(@event.event_type)
        @event.update_columns(aggregated_at: Time.current, updated_at: Time.current)
      end

      broadcaster.broadcast_event(@event)
      broadcaster.broadcast_summary
      broadcaster.broadcast_experiments if CONVERSION_EVENTS.include?(@event.event_type)
    end

    private

    def increment_rollup!(metric, dimension)
      now = Time.current
      EventRollup.upsert_all(
        [ {
          site_id: @site.id,
          bucket_date: @event.occurred_at.to_date,
          metric:,
          dimension:,
          count: 1,
          created_at: now,
          updated_at: now
        } ],
        unique_by: "idx_event_rollups_unique_bucket",
        on_duplicate: Arel.sql("count = event_rollups.count + 1, updated_at = EXCLUDED.updated_at")
      )
    end

    def record_experiment_conversion!
      attributed_assignments_for_conversion.each do |assignment|
        create_conversion!(assignment)
      end
    end

    def attributed_assignments_for_conversion
      # 归因顺序为显式实验、页面区块、通用转化，避免一次转化计入无关实验。
      # 显式归因字段不完整时直接拒绝，不能降级为通用归因。
      return [] if partial_explicit_attribution?

      explicit_assignment_for_event || section_assignment_for_event || generic_assignments_for_event
    end

    def explicit_assignment_for_event
      return nil unless @event.experiment_id && @event.variant

      experiment = @event.experiment
      return [] unless experiment
      # Explicit stamps still honor the conversion window: once a winner is applied,
      # do not keep writing new conversion rows from late/replayed events.
      return [] unless experiment.winner_applied_at.nil?
      return [] unless %w[active paused completed].include?(experiment.status)

      assignment = assignment_for(experiment)
      return [] unless assignment

      [ assignment ]
    end

    def partial_explicit_attribution?
      experiment_present = @event.experiment_id.present?
      variant_present = @event.variant_id.present?
      return true if experiment_present != variant_present
      return true if experiment_present && @event.experiment.nil?
      return true if variant_present && @event.variant.nil?

      false
    end

    def section_assignment_for_event
      section_uid = event_metadata["section_uid"].presence
      return nil unless section_uid

      experiment = @site.experiments.open_for_conversion.joins(:section).find_by(sections: { uid: section_uid })
      return [] unless experiment

      # 聚合服务不创建实验分配；分配必须在页面渲染或事件写入阶段产生。
      # 已暂停或已结束的实验只接受已有分配。
      assignment = assignment_for(experiment)
      if assignment && @event.experiment_id.blank?
        @event.update!(experiment:, variant: assignment.variant, variant_key: assignment.variant.key)
      end
      [ assignment ].compact
    end

    def generic_assignments_for_event
      # 缺少区块信息时，只向目标类型匹配的实验记录转化。
      @site.experiments.open_for_conversion.includes(:assignments).filter_map do |experiment|
        next unless experiment.primary_goal == @event.event_type || experiment.primary_goal == "any_conversion"

        assignment_for(experiment)
      end
    end

    def assignment_for(experiment)
      assignment = experiment.assignments.find_by(visitor_id: @event.visitor_id)
      return matching_assignment_or_nil(assignment) if assignment
      # Only active experiments may create assignments during aggregation (explicit event stamp path).
      return nil unless experiment.active?
      return nil unless @event.experiment_id == experiment.id && @event.variant

      experiment.assignments.create_or_find_by!(visitor_id: @event.visitor_id) do |record|
        record.variant = @event.variant
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # 并发重试仍需执行版本匹配，防止转化写入错误分配。
      matching_assignment_or_nil(experiment.assignments.find_by!(visitor_id: @event.visitor_id))
    end

    def matching_assignment_or_nil(assignment)
      return assignment unless @event.variant_id.present?
      return assignment if assignment.variant_id == @event.variant_id

      nil
    end

    def create_conversion!(assignment)
      conversion = assignment.conversions.create_or_find_by!(conversion_type: @event.event_type) do |record|
        record.event = @event
      end
      conversion.update!(event: @event) if conversion.event_id.blank?
    rescue ActiveRecord::RecordNotUnique
      assignment.conversions.find_by!(conversion_type: @event.event_type)
    end

    def broadcaster
      @broadcaster ||= Analytics::DashboardBroadcaster.new(@site)
    end

    def event_metadata
      @event.metadata.is_a?(Hash) ? @event.metadata : {}
    end
  end
end
