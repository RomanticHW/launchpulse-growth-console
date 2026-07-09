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
        # 聚合任务可能被重试，先锁住事件再判断 aggregated_at，保证 rollup 和 conversion 只写一次。
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
      # 转化归因先看显式实验，再看区块标识，最后才按通用转化处理。
      # 这个顺序能避免商品区结账被同时算进首屏、价格区等无关实验。
      # 半条显式归因比没有归因更危险，不能继续走 generic 兜底。
      return [] if partial_explicit_attribution?

      explicit_assignment_for_event || section_assignment_for_event || generic_assignments_for_event
    end

    def explicit_assignment_for_event
      return nil unless @event.experiment_id && @event.variant

      assignment = assignment_for(@event.experiment)
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

      experiment = @site.experiments.active.joins(:section).find_by(sections: { uid: section_uid })
      return [] unless experiment

      # 聚合服务不补造曝光；assignment 应该由公开运行时或事件入口在事件创建前完成。
      # 否则后台导入一条转化事件会倒推出一次访客分流，口径会变得不清楚。
      assignment = assignment_for(experiment)
      if assignment && @event.experiment_id.blank?
        @event.update!(experiment:, variant: assignment.variant, variant_key: assignment.variant.key)
      end
      [ assignment ].compact
    end

    def generic_assignments_for_event
      # 没有区块上下文时只给目标匹配的实验记转化，避免 form_submit 实验里出现 order_created 噪声记录。
      @site.experiments.active.includes(:assignments).filter_map do |experiment|
        next unless experiment.primary_goal == @event.event_type || experiment.primary_goal == "any_conversion"

        assignment_for(experiment)
      end
    end

    def assignment_for(experiment)
      assignment = experiment.assignments.find_by(visitor_id: @event.visitor_id)
      return matching_assignment_or_nil(assignment) if assignment
      return nil unless @event.experiment_id == experiment.id && @event.variant

      experiment.assignments.create_or_find_by!(visitor_id: @event.visitor_id) do |record|
        record.variant = @event.variant
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # 并发兜底也要走同一套版本匹配检查，不能因为重试路径把转化写到错误 assignment 上。
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
