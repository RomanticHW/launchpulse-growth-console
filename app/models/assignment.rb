class Assignment < ApplicationRecord
  belongs_to :experiment
  belongs_to :variant
  has_many :conversions, dependent: :destroy

  # 分配记录中的版本必须属于同一个实验。
  validates :visitor_id, presence: true, uniqueness: { scope: :experiment_id }
  validate :variant_belongs_to_experiment

  private

  def variant_belongs_to_experiment
    return unless variant && experiment

    errors.add(:variant, "must belong to the assignment experiment") if variant.experiment != experiment
  end
end
