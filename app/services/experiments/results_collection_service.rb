module Experiments
  class ResultsCollectionService
    def initialize(experiments)
      @experiments = experiments.to_a
    end

    def call
      variants_by_experiment = variants.group_by(&:experiment_id)
      stats = stats_by_variant

      @experiments.each_with_object({}) do |experiment, result|
        experiment_variants = variants_by_experiment.fetch(experiment.id, [])
        result[experiment.id] = Experiments::ResultsService.new(
          ExperimentWithVariants.new(experiment, experiment_variants),
          stats_by_variant: stats
        ).call
      end
    end

    private

    def variants
      @variants ||= Variant.where(experiment_id: @experiments.map(&:id)).order(:id).to_a
    end

    def stats_by_variant
      visitor_counts.each_with_object({}) do |(variant_id, visitors), result|
        result[variant_id] = {
          visitors:,
          conversions: conversion_counts.fetch(variant_id, 0)
        }
      end
    end

    def visitor_counts
      @visitor_counts ||= Assignment.where(variant_id: variant_ids).group(:variant_id).count
    end

    def conversion_counts
      @conversion_counts ||= Conversion
        .joins(assignment: :experiment)
        .where(assignments: { variant_id: variant_ids })
        .where("experiments.primary_goal = ? OR conversions.conversion_type = experiments.primary_goal", "any_conversion")
        .group("assignments.variant_id")
        .distinct
        .count("assignments.id")
    end

    def variant_ids
      @variant_ids ||= variants.map(&:id)
    end

    class ExperimentWithVariants
      attr_reader :variants

      def initialize(experiment, variants)
        @experiment = experiment
        @variants = variants
      end

      def method_missing(method_name, ...)
        @experiment.public_send(method_name, ...)
      end

      def respond_to_missing?(method_name, include_private = false)
        @experiment.respond_to?(method_name, include_private) || super
      end
    end
  end
end
