class ApiKey < ApplicationRecord
  belongs_to :site

  scope :active, -> { where(active: true) }

  validates :name, :token_digest, presence: true
  validates :token_digest, uniqueness: true

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def self.issue!(site:, name: "Tracking API")
    token = SecureRandom.hex(24)
    key = create!(site:, name:, token_digest: digest(token))
    [ key, token ]
  end

  def signed_token(raw_token)
    Rails.application.message_verifier(:site_tracking).generate({ site_id:, token: raw_token })
  end
end
