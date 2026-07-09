class EventRollup < ApplicationRecord
  belongs_to :site

  validates :bucket_date, :metric, :dimension, presence: true
  validates :count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :dimension, uniqueness: { scope: [ :site_id, :bucket_date, :metric ] }
end
