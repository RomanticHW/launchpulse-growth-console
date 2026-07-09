class SectionPatch < ApplicationRecord
  STATUSES = %w[pending applied reverted testing tested dismissed superseded].freeze

  belongs_to :recommendation
  belongs_to :section

  # 补丁快照是建议生成时的证据，后续应用或回滚只能移动 section.props，不能重写 before/after。
  validates :props_diff, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :section_matches_recommendation

  def apply!
    return self if status == "applied"
    unless %w[pending reverted].include?(status)
      errors.add(:base, "#{status.humanize} patches cannot be applied")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      target_props = after_props.presence || section.props.deep_merge(props_diff)
      update!(
        status: "applied",
        applied: true,
        before_props: before_props.presence || section.props,
        after_props: target_props,
        applied_at: Time.current,
        reverted_at: nil
      )
      section.update!(props: target_props)
      recommendation.update!(status: "applied", applied_at: Time.current)
    end
  end

  def revert!
    unless status == "applied" && applied_at.present?
      errors.add(:base, "Patch has not been applied")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      section.update!(props: before_props)
      update!(status: "reverted", applied: false, reverted_at: Time.current)
      recommendation.update!(status: "open", applied_at: nil)
    end
  end

  def dismiss!
    unless %w[pending reverted].include?(status)
      errors.add(:base, "#{status.humanize} patches cannot be dismissed")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(status: "dismissed")
    recommendation.update!(status: "dismissed", dismissed_at: Time.current)
  end

  private

  def section_matches_recommendation
    return unless recommendation&.section && section

    errors.add(:section, "must match the recommendation section") if section != recommendation.section
  end
end
