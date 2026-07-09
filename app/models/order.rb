class Order < ApplicationRecord
  belongs_to :site
  has_many :order_items, dependent: :destroy

  validates :number, :email, presence: true
  validates :number, uniqueness: { scope: :site_id }
  validates :total, numericality: { greater_than_or_equal_to: 0 }
end
