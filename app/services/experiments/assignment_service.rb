module Experiments
  class AssignmentService
    VariantConflict = Class.new(StandardError)

    def initialize(experiment)
      @experiment = experiment
    end

    def assign(visitor_id, variant: nil)
      # 默认事务会加入调用方事务，让 site → experiment 锁序覆盖后续 Event/Order/Form 写入直到最终提交。
      ActiveRecord::Base.transaction do
        # KEY SHARE 允许不同实验并发分流，同时会和生命周期操作的 site FOR UPDATE 串行。
        Site.lock("FOR KEY SHARE").find(@experiment.site_id)

        @experiment.with_lock do
          @experiment.reload
          return nil unless @experiment.status == "active"
          validate_requested_variant!(variant)

          existing = @experiment.assignments.find_by(visitor_id:)
          return matching_assignment(existing, variant) if existing

          variants = @experiment.variants.order(:id).to_a
          raise ArgumentError, "experiment has no variants" if variants.empty?

          selected_variant = variant || weighted_variant_for(variants, visitor_id)

          begin
            @experiment.assignments.create_or_find_by!(visitor_id:) do |assignment|
              assignment.variant = selected_variant
            end
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
            recover_unique_assignment(error, visitor_id, variant)
          end
        end
      end
    end

    private

    def validate_requested_variant!(requested_variant)
      return unless requested_variant
      return if requested_variant.experiment_id == @experiment.id

      raise VariantConflict, "requested variant belongs to another experiment"
    end

    def recover_unique_assignment(error, visitor_id, requested_variant)
      if error.is_a?(ActiveRecord::RecordInvalid) && !visitor_uniqueness_error?(error)
        raise error
      end

      assignment = @experiment.assignments.find_by(visitor_id:)
      raise error unless assignment

      matching_assignment(assignment, requested_variant)
    end

    def visitor_uniqueness_error?(error)
      details = error.record.errors.details
      details.keys == [ :visitor_id ] && details.fetch(:visitor_id).all? { |detail| detail.fetch(:error) == :taken }
    end

    def matching_assignment(assignment, requested_variant)
      if requested_variant && assignment.variant_id != requested_variant.id
        raise VariantConflict, "assignment conflicts with requested variant"
      end

      assignment
    end

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
