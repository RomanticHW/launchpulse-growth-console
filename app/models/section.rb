class Section < ApplicationRecord
  KINDS = %w[hero feature_grid testimonial contact_form product_grid pricing faq].freeze

  belongs_to :page
  has_one :site, through: :page
  has_many :ai_findings, dependent: :nullify
  has_many :recommendations, dependent: :nullify
  has_many :section_patches, dependent: :destroy
  has_many :experiments, dependent: :nullify
  has_many :forms, dependent: :nullify

  before_validation :ensure_uid

  validates :kind, inclusion: { in: KINDS }
  validates :uid, presence: true, uniqueness: true
  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def ensure_uid
    self.uid ||= SecureRandom.uuid
  end
end
