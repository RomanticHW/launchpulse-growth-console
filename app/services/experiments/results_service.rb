module Experiments
  class ResultsService
    def initialize(experiment, stats_by_variant: nil)
      @experiment = experiment
      @stats_by_variant = stats_by_variant
    end

    def call
      control = variants.find { |variant| variant.role == "control" } || variants.first
      control_stats = stats_for(control)

      variants.map do |variant|
        stats = stats_for(variant)
        comparison = compare_to_control(stats, control_stats, variant == control)

        {
          variant:,
          visitors: stats.fetch(:visitors),
          conversions: stats.fetch(:conversions),
          conversion_rate: stats.fetch(:conversion_rate),
          absolute_delta_vs_control: comparison.fetch(:absolute_delta),
          lift_vs_control: comparison.fetch(:lift),
          lift: comparison.fetch(:lift),
          lift_label: comparison.fetch(:lift_label),
          confidence: comparison.fetch(:confidence),
          label: label_for(variant, control, stats, control_stats, comparison)
        }
      end
    end

    private

    def variants
      @variants ||= @experiment.variants.sort_by(&:id)
    end

    def stats_for(variant)
      visitors = visitors_count_for(variant)
      conversions = conversions_count_for(variant)
      conversion_rate = visitors.zero? ? 0.to_d : (conversions.to_d / visitors * 100).round(2)

      { visitors:, conversions:, conversion_rate: }
    end

    def visitors_count_for(variant)
      return 0 unless variant
      return @stats_by_variant.fetch(variant.id, {}).fetch(:visitors, 0).to_i if @stats_by_variant

      variant.visitors_count.to_i
    end

    def conversions_count_for(variant)
      return 0 unless variant
      return @stats_by_variant.fetch(variant.id, {}).fetch(:conversions, 0).to_i if @stats_by_variant

      scope = variant.conversions
      scope = scope.where(conversion_type: @experiment.primary_goal) unless @experiment.primary_goal == "any_conversion"
      scope.select(:assignment_id).distinct.count
    end

    def compare_to_control(stats, control_stats, control_row)
      # 这里用透明的近似算法展示趋势；生产实验平台还需要更严谨的统计策略。
      return { absolute_delta: 0.to_d, lift: 0.to_d, lift_label: "基准版本", confidence: 0 } if control_row

      control_rate = control_stats.fetch(:conversion_rate)
      conversion_rate = stats.fetch(:conversion_rate)
      absolute_delta = (conversion_rate - control_rate).round(2)
      lift = lift_for(control_rate, conversion_rate, absolute_delta)

      {
        absolute_delta:,
        lift:,
        lift_label: lift_label_for(lift, control_rate, conversion_rate),
        confidence: confidence_for(stats, control_stats, absolute_delta)
      }
    end

    def lift_for(control_rate, conversion_rate, absolute_delta)
      return nil if control_rate.zero? && conversion_rate.positive?
      return 0.to_d if control_rate.zero?

      ((absolute_delta / control_rate) * 100).round(2)
    end

    def lift_label_for(lift, control_rate, conversion_rate)
      return "从 0 基准起步" if lift.nil? && control_rate.zero? && conversion_rate.positive?

      "提升 #{lift}%"
    end

    def confidence_for(stats, control_stats, absolute_delta)
      return 0 if stats.fetch(:visitors).zero? || control_stats.fetch(:visitors).zero?

      variant_rate = stats.fetch(:conversions).to_f / stats.fetch(:visitors)
      control_rate = control_stats.fetch(:conversions).to_f / control_stats.fetch(:visitors)
      pooled = (stats.fetch(:conversions) + control_stats.fetch(:conversions)).to_f / (stats.fetch(:visitors) + control_stats.fetch(:visitors))
      standard_error = Math.sqrt(pooled * (1 - pooled) * ((1.0 / stats.fetch(:visitors)) + (1.0 / control_stats.fetch(:visitors))))
      return 0 if standard_error.zero?

      z_score = (variant_rate - control_rate) / standard_error
      probability = normal_cdf(absolute_delta.negative? ? -z_score : z_score)
      (probability * 100).round.clamp(0, 99)
    end

    def normal_cdf(z_score)
      0.5 * (1 + Math.erf(z_score / Math.sqrt(2)))
    end

    def label_for(variant, control, stats, control_stats, comparison)
      return "原版本" if variant == control
      return "数据不足" if stats.fetch(:visitors) < 50 || control_stats.fetch(:visitors) < 50

      confidence = comparison.fetch(:confidence)
      lift = comparison.fetch(:lift)
      absolute_delta = comparison.fetch(:absolute_delta)
      return "暂时领先" if absolute_delta.positive? && confidence >= 80
      return "表现偏弱" if lift&.negative? && confidence >= 80

      "数据不足"
    end
  end
end
