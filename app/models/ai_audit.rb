class AiAudit < ApplicationRecord
  belongs_to :site
  has_many :ai_findings, dependent: :destroy

  validates :status, presence: true
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end
