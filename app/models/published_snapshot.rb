class PublishedSnapshot < ApplicationRecord
  belongs_to :site
  belongs_to :published_by, class_name: "User", optional: true

  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :site_id }
  validates :payload, presence: true
end
