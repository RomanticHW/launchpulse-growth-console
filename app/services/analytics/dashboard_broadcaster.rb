module Analytics
  class DashboardBroadcaster
    SUMMARY_THROTTLE_WINDOW = 3.seconds
    EXPERIMENTS_THROTTLE_WINDOW = 3.seconds

    def initialize(site)
      @site = site
    end

    def broadcast_event(event)
      # 统计写入与页面广播分开，调整频道或限流策略不会改变统计口径。
      Turbo::StreamsChannel.broadcast_prepend_to(
        event_stream_name,
        target: "event_stream",
        partial: "events/event",
        locals: { event: }
      )
    end

    def broadcast_summary(force: false)
      unless force
        claimed = claim_broadcast_slot("summary", SUMMARY_THROTTLE_WINDOW)
        unless claimed
          schedule_trailing_refresh(:summary)
          return
        end
      end

      Turbo::StreamsChannel.broadcast_replace_to(
        metrics_stream_name,
        target: "analytics_summary",
        partial: "sites/analytics_summary",
        locals: { site: @site, summary: Analytics::SummaryService.new(@site).call }
      )
    end

    def broadcast_experiments(force: false)
      unless force
        claimed = claim_broadcast_slot("experiments", EXPERIMENTS_THROTTLE_WINDOW)
        unless claimed
          schedule_trailing_refresh(:experiments)
          return
        end
      end

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

    def schedule_trailing_refresh(kind)
      schedule_key = "dashboard_broadcast:#{kind}:scheduled:site:#{@site.id}"
      window = kind.to_s == "experiments" ? EXPERIMENTS_THROTTLE_WINDOW : SUMMARY_THROTTLE_WINDOW
      return unless Rails.cache.write(schedule_key, true, expires_in: window, unless_exist: true)

      DashboardRefreshJob.set(wait: window).perform_later(@site.id, kind.to_s)
    end
  end
end
