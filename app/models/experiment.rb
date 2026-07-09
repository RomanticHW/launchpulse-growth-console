class Experiment < ApplicationRecord
  STATUSES = %w[draft active paused completed].freeze
  GOALS = %w[form_submit order_created any_conversion].freeze

  belongs_to :site
  belongs_to :recommendation, optional: true
  belongs_to :section, optional: true
  belongs_to :winner_variant, class_name: "Variant", optional: true
  has_many :variants, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :conversions, through: :assignments

  before_destroy :clear_winner_variant_reference

  scope :active, -> { where(status: "active") }
  # Semantic alias of active; kept separate so future rules can diverge without call-site churn.
  scope :accepting_new_assignments, -> { active }
  # Late conversions still count until a winner is applied.
  scope :open_for_conversion, -> {
    where(status: %w[active paused completed], winner_applied_at: nil)
  }

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :primary_goal, inclusion: { in: GOALS }
  validate :section_belongs_to_site
  validate :recommendation_belongs_to_site
  validate :winner_variant_belongs_to_experiment

  def active?
    status == "active"
  end

  def visitors_count
    assignments.count
  end

  def conversions_count
    scope = conversions
    scope = scope.where(conversion_type: primary_goal) unless primary_goal == "any_conversion"
    scope.select(:assignment_id).distinct.count
  end

  def conversion_rate
    return 0.to_d if visitors_count.zero?

    (conversions_count.to_d / visitors_count * 100).round(2)
  end

  private

  def section_belongs_to_site
    return unless section && site

    errors.add(:section, "must belong to the experiment site") if section.site != site
  end

  def recommendation_belongs_to_site
    return unless recommendation && site

    errors.add(:recommendation, "must belong to the experiment site") if recommendation.site != site
  end

  def winner_variant_belongs_to_experiment
    return unless winner_variant

    errors.add(:winner_variant, "must belong to the experiment") if winner_variant.experiment != self
  end

  def clear_winner_variant_reference
    # winner_variant 是 experiment 指向自身 variant 的父子反向引用；销毁前先断开，避免数据库外键卡住重置种子数据。
    update_column(:winner_variant_id, nil) if winner_variant_id.present?
  end
end
