class Account < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :sites, dependent: :destroy
  has_many :audit_logs, dependent: :destroy

  validates :name, presence: true
  validates :plan, presence: true
end
