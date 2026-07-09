class Membership < ApplicationRecord
  OWNER = "owner"
  MARKETER = "marketer"
  VIEWER = "viewer"
  ROLES = [ OWNER, MARKETER, VIEWER ].freeze

  belongs_to :account
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :account_id }
end
