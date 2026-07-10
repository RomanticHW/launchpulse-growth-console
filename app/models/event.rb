class Event < ApplicationRecord
  TYPES = %w[page_view cta_click form_start form_submit product_view checkout_click order_created].freeze
  SOURCES = %w[direct search social email referral paid].freeze
  DEVICES = %w[desktop mobile tablet].freeze

  belongs_to :site
  belongs_to :page, optional: true
  belongs_to :experiment, optional: true
  belongs_to :variant, optional: true

  # 归因字段必须相互一致，防止无效事件进入聚合和实验结果。
  validates :event_type, inclusion: { in: TYPES }
  validates :visitor_id, :occurred_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :device, inclusion: { in: DEVICES }
  validates :idempotency_key, uniqueness: { scope: :site_id }, allow_blank: true
  # 带幂等键的事件必须保存请求指纹，模型层和服务层共同保证该约束。
  validates :payload_fingerprint, presence: true, if: -> { idempotency_key.present? }
  validate :page_belongs_to_site
  validate :experiment_belongs_to_site
  validate :variant_belongs_to_experiment
  validate :variant_key_matches_variant
  validate :metadata_is_object

  scope :recent, -> { order(occurred_at: :desc) }
  scope :conversions, -> { where(event_type: Conversion::EVENT_TYPES) }

  private

  def page_belongs_to_site
    return unless page && site

    errors.add(:page, "must belong to the event site") if page.site != site
  end

  def experiment_belongs_to_site
    return unless experiment && site

    errors.add(:experiment, "must belong to the event site") if experiment.site != site
  end

  def variant_belongs_to_experiment
    return unless variant

    if experiment
      errors.add(:variant, "must belong to the event experiment") if variant.experiment != experiment
    elsif variant.experiment.site != site
      errors.add(:variant, "must belong to the event site")
    end
  end

  def variant_key_matches_variant
    return unless variant && variant_key.present?

    errors.add(:variant_key, "must match the event variant") if variant_key != variant.key
  end

  def metadata_is_object
    errors.add(:metadata, "must be an object") unless metadata.is_a?(Hash)
  end
end
