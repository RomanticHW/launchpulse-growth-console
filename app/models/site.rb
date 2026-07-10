class Site < ApplicationRecord
  STATUSES = %w[draft published archived].freeze

  belongs_to :account
  has_many :forms, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :sections, through: :pages
  has_many :published_snapshots, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :event_rollups, dependent: :destroy
  has_many :ai_audits, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :experiments, dependent: :destroy
  has_many :contacts, dependent: :destroy
  # 订单项引用商品，删除站点时必须先删除订单再删除商品。
  has_many :orders, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  validates :name, :slug, :industry, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  # Public routes resolve by slug alone (/s/:slug), so uniqueness must be global.
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :growth_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def home_page
    pages.order(:position).first
  end

  def latest_snapshot
    published_snapshots.order(version: :desc).first
  end
end
