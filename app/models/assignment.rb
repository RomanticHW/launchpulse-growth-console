class Assignment < ApplicationRecord
  belongs_to :experiment
  belongs_to :variant
  has_many :conversions, dependent: :destroy

  # assignment 是实验数据的基础边界，variant 不能串到另一个 experiment。
  validates :visitor_id, presence: true, uniqueness: { scope: :experiment_id }
  validate :variant_belongs_to_experiment

  private

  def variant_belongs_to_experiment
    return unless variant && experiment

    errors.add(:variant, "must belong to the assignment experiment") if variant.experiment != experiment
  end
end
