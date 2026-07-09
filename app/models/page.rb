class Page < ApplicationRecord
  belongs_to :site
  has_many :sections, -> { order(:position) }, dependent: :destroy, inverse_of: :page
  has_many :events, dependent: :nullify

  validates :title, :path, presence: true
  validates :path, uniqueness: { scope: :site_id }
end
