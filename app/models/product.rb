class Product < ApplicationRecord
  belongs_to :site
  has_many :order_items, dependent: :restrict_with_error

  before_validation :ensure_key

  # key 是 checkout 业务标识，展示名可以改，订单映射不能跟着文案漂移。
  validates :name, :key, presence: true
  validates :key, uniqueness: { scope: :site_id }, format: { with: /\A[a-z0-9-]+\z/ }
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  private

  def ensure_key
    self.key = name.to_s.parameterize if key.blank?
  end
end
