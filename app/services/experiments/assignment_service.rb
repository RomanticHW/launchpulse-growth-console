module Experiments
  class AssignmentService
    def initialize(experiment)
      @experiment = experiment
    end

    def assign(visitor_id)
      existing = @experiment.assignments.find_by(visitor_id:)
      return existing if existing

      variants = @experiment.variants.order(:id).to_a
      raise ArgumentError, "experiment has no variants" if variants.empty?

      variant = weighted_variant_for(variants, visitor_id)

      @experiment.assignments.create_or_find_by!(visitor_id:) do |assignment|
        assignment.variant = variant
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      @experiment.assignments.find_by!(visitor_id:)
    end

    private

    def weighted_variant_for(variants, visitor_id)
      # 使用访客与实验的稳定哈希，同一访客持续看到相同版本。
      total_weight = variants.sum { |variant| variant.weight.to_i.positive? ? variant.weight.to_i : 0 }
      return equal_split_variant_for(variants, visitor_id) if total_weight <= 0

      bucket = Zlib.crc32("#{@experiment.id}:#{visitor_id}") % total_weight
      cumulative = 0
      variants.each do |variant|
        cumulative += [ variant.weight.to_i, 0 ].max
        return variant if bucket < cumulative
      end
      variants.last
    end

    def equal_split_variant_for(variants, visitor_id)
      variants[Zlib.crc32("#{@experiment.id}:#{visitor_id}") % variants.size]
    end
  end
end
