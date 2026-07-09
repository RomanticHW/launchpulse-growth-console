class FormField < ApplicationRecord
  FIELD_TYPES = %w[email text textarea select checkbox phone].freeze

  belongs_to :form

  before_validation :ensure_key

  # 表单字段的 key 用于 submission payload，label 只是展示文案，后续可以安全改名。
  validates :label, :field_type, :key, presence: true
  validates :field_type, inclusion: { in: FIELD_TYPES }
  validates :key, uniqueness: { scope: :form_id }, format: { with: /\A[a-z0-9_]+\z/ }

  def param_key
    key
  end

  private

  def ensure_key
    self.key = label.to_s.parameterize.underscore if key.blank?
  end
end
