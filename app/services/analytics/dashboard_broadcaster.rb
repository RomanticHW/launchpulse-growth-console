module Analytics
  class DashboardBroadcaster
    SUMMARY_THROTTLE_WINDOW = 3.seconds
    EXPERIMENTS_THROTTLE_WINDOW = 3.seconds

    def initialize(site)
      @site = site
    end

    def broadcast_event(event)
      # 聚合只负责写统计结果；实时刷新单独放在这里，后续要换频道或限流，不会影响统计口径。
      Turbo::StreamsChannel.broadcast_prepend_to(
        event_stream_name,
        target: "event_stream",
        partial: "events/event",
        locals: { event: }
      )
    end

    def broadcast_summary
      return unless claim_broadcast_slot("summary", SUMMARY_THROTTLE_WINDOW)

      Turbo::StreamsChannel.broadcast_replace_to(
        metrics_stream_name,
        target: "analytics_summary",
        partial: "sites/analytics_summary",
        locals: { site: @site, summary: Analytics::SummaryService.new(@site).call }
      )
    end

    def broadcast_experiments
      return unless claim_broadcast_slot("experiments", EXPERIMENTS_THROTTLE_WINDOW)

      experiments = @site.experiments.includes(:section, :variants).order(created_at: :desc)
      Turbo::StreamsChannel.broadcast_replace_to(
        metrics_stream_name,
        target: "experiments_panel",
        partial: "sites/experiments",
        locals: {
          site: @site,
          experiments:,
          experiment_results: Experiments::ResultsCollectionService.new(experiments).call
        }
      )
    end

    private

    def event_stream_name
      "site_#{@site.id}_events"
    end

    def metrics_stream_name
      "site_#{@site.id}_metrics"
    end

    def claim_broadcast_slot(kind, expires_in)
      Rails.cache.write(throttle_key(kind), true, expires_in:, unless_exist: true)
    end

    def throttle_key(kind)
      "dashboard_broadcast:#{kind}:site:#{@site.id}"
    end
  end
end
