class Membership < ApplicationRecord
  ROLES = %w[owner marketer viewer].freeze

  belongs_to :account
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :account_id }
end
