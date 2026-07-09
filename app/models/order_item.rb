class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validate :product_belongs_to_order_site

  private

  def product_belongs_to_order_site
    return unless product && order

    errors.add(:product, "must belong to the order site") if product.site != order.site
  end
end
