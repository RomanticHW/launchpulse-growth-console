module Analytics
  class SummaryService
    def initialize(site, since: 14.days.ago)
      @site = site
      # Align raw event windows with daily rollup buckets (calendar days in app TZ).
      @since = since.in_time_zone.beginning_of_day
      @events = site.events.where(occurred_at: @since..)
    end

    def call
      page_views = rollup_count_with_unaggregated_raw("event:page_view", "all", event_type: "page_view")
      unique_visitors = @events.distinct.count(:visitor_id)
      conversions = @events.where(event_type: %w[form_submit order_created]).distinct.count(:visitor_id)

      {
        page_views:,
        unique_visitors:,
        conversions:,
        conversion_rate: rate(conversions, unique_visitors),
        top_sources: rollup_ranked_with_unaggregated_raw("page_view_source", :source, event_type: "page_view"),
        top_devices: rollup_ranked_with_unaggregated_raw("page_view_device", :device, event_type: "page_view"),
        funnel: funnel
      }
    end

    private

    def ranked(column, event_type: nil)
      scope = event_type ? @events.where(event_type:) : @events
      scope.group(column).order(Arel.sql("count_all DESC")).limit(5).count
    end

    def rollup_count_with_unaggregated_raw(metric, dimension, event_type:)
      rollup_scope = rollups.where(metric:, dimension:)
      raw_count = unaggregated_events.where(event_type:).count
      return @events.where(event_type:).count unless rollup_scope.exists?

      rollup_scope.sum(:count) + raw_count
    end

    def rollup_ranked_with_unaggregated_raw(metric, column, event_type: nil)
      rollup_scope = rollups.where(metric:)
      return ranked(column, event_type:) unless rollup_scope.exists?

      merged = rollup_scope.group(:dimension).sum(:count)
      raw_scope = event_type ? unaggregated_events.where(event_type:) : unaggregated_events
      raw_scope.group(column).count.each do |dimension, count|
        merged[dimension] = merged.fetch(dimension, 0) + count
      end
      merged.sort_by { |_dimension, count| -count }.first(5).to_h
    end

    def rollups
      @rollups ||= @site.event_rollups.where(bucket_date: @since.to_date..)
    end

    def unaggregated_events
      @unaggregated_events ||= @events.where(aggregated_at: nil)
    end

    def funnel
      {
        "page_view" => @events.where(event_type: "page_view").distinct.count(:visitor_id),
        "cta_click" => @events.where(event_type: "cta_click").distinct.count(:visitor_id),
        "form_submit_or_order" => @events.where(event_type: %w[form_submit order_created]).distinct.count(:visitor_id)
      }
    end

    def rate(numerator, denominator)
      return 0.to_d if denominator.zero?

      (numerator.to_d / denominator * 100).round(2)
    end
  end
end
