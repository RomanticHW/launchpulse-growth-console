class Contact < ApplicationRecord
  belongs_to :site
  has_many :form_submissions, dependent: :nullify

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :site_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
end
