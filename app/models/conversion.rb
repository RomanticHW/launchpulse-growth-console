class Conversion < ApplicationRecord
  TYPES = %w[form_submit order_created any_conversion].freeze
  EVENT_TYPES = TYPES.excluding("any_conversion").freeze

  belongs_to :assignment
  belongs_to :event, optional: true

  # 转化必须绑定同一访客在同一站点的行为，跨站或换访客都会让实验结果失真。
  validates :conversion_type, presence: true
  validates :conversion_type, inclusion: { in: TYPES }
  validates :conversion_type, uniqueness: { scope: :assignment_id }
  validate :event_matches_assignment

  private

  def event_matches_assignment
    return unless event && assignment

    if event.site != assignment.experiment.site
      errors.add(:event, "must belong to the assignment site")
    end
    if event.visitor_id != assignment.visitor_id
      errors.add(:event, "visitor must match the assignment")
    end
    if event.experiment_id.present? && event.experiment_id != assignment.experiment_id
      errors.add(:event, "experiment must match the assignment")
    end
    if event.variant_id.present? && event.variant_id != assignment.variant_id
      errors.add(:event, "variant must match the assignment")
    end
  end
end
