class Variant < ApplicationRecord
  ROLES = %w[control variant].freeze

  belongs_to :experiment
  has_many :assignments, dependent: :destroy
  has_many :conversions, through: :assignments

  validates :name, :key, :role, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :weight, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :key, uniqueness: { scope: :experiment_id }

  def visitors_count
    assignments.count
  end

  def conversions_count
    scope = conversions
    scope = scope.where(conversion_type: experiment.primary_goal) unless experiment.primary_goal == "any_conversion"
    scope.select(:assignment_id).distinct.count
  end

  def conversion_rate
    return 0.to_d if visitors_count.zero?

    (conversions_count.to_d / visitors_count * 100).round(2)
  end
end
