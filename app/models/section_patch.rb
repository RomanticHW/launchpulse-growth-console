class SectionPatch < ApplicationRecord
  STATUSES = %w[pending applied reverted testing tested dismissed superseded].freeze

  belongs_to :recommendation
  belongs_to :section

  # 补丁保存修改前后内容，应用和撤回不能重写这两份记录。
  validates :props_diff, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :section_matches_recommendation

  def apply!
    section.site.with_lock do
      with_lock do
        if status == "applied"
          self
        else
          unless %w[pending reverted].include?(status)
            errors.add(:base, "#{status.humanize} patches cannot be applied")
            raise ActiveRecord::RecordInvalid, self
          end

          current_section = section.reload
          target_props = after_props.presence || current_section.props.deep_merge(props_diff)
          update!(
            status: "applied",
            applied: true,
            before_props: before_props.presence || current_section.props,
            after_props: target_props,
            applied_at: Time.current,
            reverted_at: nil
          )
          current_section.update!(props: target_props)
          recommendation.update!(status: "applied", applied_at: Time.current)
        end
      end
    end
  end

  def revert!
    section.site.with_lock do
      with_lock do
        unless status == "applied" && applied_at.present?
          errors.add(:base, "Patch has not been applied")
          raise ActiveRecord::RecordInvalid, self
        end

        section.update!(props: before_props)
        update!(status: "reverted", applied: false, reverted_at: Time.current)
        recommendation.update!(status: "open", applied_at: nil)
      end
    end
  end

  def dismiss!
    section.site.with_lock do
      with_lock do
        unless %w[pending reverted].include?(status)
          errors.add(:base, "#{status.humanize} patches cannot be dismissed")
          raise ActiveRecord::RecordInvalid, self
        end

        update!(status: "dismissed")
        recommendation.update!(status: "dismissed", dismissed_at: Time.current)
      end
    end
  end

  private

  def section_matches_recommendation
    return unless recommendation&.section && section

    errors.add(:section, "must match the recommendation section") if section != recommendation.section
  end
end
