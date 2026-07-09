class AiFinding < ApplicationRecord
  belongs_to :ai_audit
  belongs_to :section, optional: true
  has_many :recommendations, dependent: :destroy

  validates :problem, :severity, presence: true
end
