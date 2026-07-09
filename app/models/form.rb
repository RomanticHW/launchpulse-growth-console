class Form < ApplicationRecord
  belongs_to :site
  belongs_to :section, optional: true
  has_many :form_fields, -> { order(:position) }, dependent: :destroy
  has_many :form_submissions, dependent: :destroy

  validates :name, presence: true
  validate :section_belongs_to_site

  private

  def section_belongs_to_site
    return unless section && site

    errors.add(:section, "must belong to the form site") if section.site != site
  end
end
