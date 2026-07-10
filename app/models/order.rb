class Order < ApplicationRecord
  REQUEST_TOKEN_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  REQUEST_TOKEN_INDEX_NAME = "idx_orders_unique_request_token"

  belongs_to :site
  has_many :order_items, dependent: :destroy

  validates :number, :email, presence: true
  validates :number, uniqueness: { scope: :site_id }
  validates :request_token,
    length: { maximum: 100 },
    format: { with: REQUEST_TOKEN_FORMAT },
    uniqueness: { scope: :site_id },
    allow_nil: true
  validates :total, numericality: { greater_than_or_equal_to: 0 }
end
