class FormSubmission < ApplicationRecord
  REQUEST_TOKEN_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  REQUEST_TOKEN_INDEX_NAME = "idx_form_submissions_unique_request_token"

  belongs_to :form
  belongs_to :contact, optional: true

  validates :payload, presence: true
  validates :request_token,
    length: { maximum: 100 },
    format: { with: REQUEST_TOKEN_FORMAT },
    uniqueness: { scope: :form_id },
    allow_nil: true
end
