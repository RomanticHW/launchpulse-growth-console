class AuditLog < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :site, optional: true

  validates :action, presence: true
end
