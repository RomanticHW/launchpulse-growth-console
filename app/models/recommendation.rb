class Recommendation < ApplicationRecord
  STATUSES = %w[open testing tested applied dismissed superseded].freeze

  belongs_to :site
  belongs_to :ai_finding
  belongs_to :section, optional: true
  has_one :section_patch, dependent: :destroy
  has_many :experiments, dependent: :nullify

  scope :open, -> { where(status: "open") }

  validates :title, :problem, :expected_impact, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validate :section_belongs_to_site
  validate :finding_section_matches

  private

  def section_belongs_to_site
    return unless section && site

    errors.add(:section, "must belong to the recommendation site") if section.site != site
  end

  def finding_section_matches
    return unless ai_finding&.section && section

    errors.add(:ai_finding, "must reference the recommendation section") if ai_finding.section != section
  end
end
