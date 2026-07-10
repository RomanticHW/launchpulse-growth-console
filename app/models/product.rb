class Product < ApplicationRecord
  belongs_to :site
  has_many :order_items, dependent: :restrict_with_error

  before_validation :ensure_key

  # 商品 `key` 用于购买路径，展示名称可以独立修改。
  validates :name, :key, presence: true
  validates :key, uniqueness: { scope: :site_id }, format: { with: /\A[a-z0-9-]+\z/ }
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  private

  def ensure_key
    self.key = name.to_s.parameterize if key.blank?
  end
end
