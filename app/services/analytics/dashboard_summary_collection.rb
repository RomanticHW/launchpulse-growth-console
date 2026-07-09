module Analytics
  class DashboardSummaryCollection
    def initialize(sites, since: 14.days.ago)
      @sites = sites.to_a
      @since = since
    end

    def call
      @sites.each_with_object({}) do |site, result|
        unique = unique_visitors.fetch(site.id, 0)
        conversions = conversion_visitors.fetch(site.id, 0)

        result[site.id] = {
          page_views: page_views_for(site),
          conversion_rate: rate(conversions, unique),
          conversion_trend: conversion_trend_for(site)
        }
      end
    end

    private

    def conversion_trend_for(site)
      trend_dates.map do |date|
        visitors = daily_unique_visitors.fetch([ site.id, date ], 0)
        conversions = daily_conversion_visitors.fetch([ site.id, date ], 0)
        rate(conversions, visitors)
      end
    end

    def trend_dates
      @trend_dates ||= (@since.to_date..Date.current).to_a.last(14)
    end

    def daily_unique_visitors
      @daily_unique_visitors ||= daily_counts(events)
    end

    def daily_conversion_visitors
      @daily_conversion_visitors ||= daily_counts(events.where(event_type: %w[form_submit order_created]))
    end

    def daily_counts(scope)
      scope
        .group(:site_id, day_expression)
        .distinct
        .count(:visitor_id)
        .transform_keys { |site_id, day| [ site_id, day.to_date ] }
    end

    def day_expression
      Arel.sql("DATE(occurred_at)")
    end

    def page_views_for(site)
      return raw_page_views.fetch(site.id, 0) unless rolled_site_ids.include?(site.id)

      rolled_page_views.fetch(site.id, 0) + unaggregated_page_views.fetch(site.id, 0)
    end

    def rolled_site_ids
      @rolled_site_ids ||= rolled_page_views.keys.to_set
    end

    def rolled_page_views
      @rolled_page_views ||= EventRollup
        .where(site_id: site_ids, bucket_date: @since.to_date.., metric: "event:page_view", dimension: "all")
        .group(:site_id)
        .sum(:count)
    end

    def raw_page_views
      @raw_page_views ||= events.where(event_type: "page_view").group(:site_id).count
    end

    def unaggregated_page_views
      @unaggregated_page_views ||= events.where(event_type: "page_view", aggregated_at: nil).group(:site_id).count
    end

    def unique_visitors
      @unique_visitors ||= events.distinct.group(:site_id).count(:visitor_id)
    end

    def conversion_visitors
      @conversion_visitors ||= events.where(event_type: %w[form_submit order_created]).distinct.group(:site_id).count(:visitor_id)
    end

    def events
      @events ||= Event.where(site_id: site_ids, occurred_at: @since..)
    end

    def site_ids
      @site_ids ||= @sites.map(&:id)
    end

    def rate(numerator, denominator)
      return 0.to_d if denominator.zero?

      (numerator.to_d / denominator * 100).round(2)
    end
  end
end
