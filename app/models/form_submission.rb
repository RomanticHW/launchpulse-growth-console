class FormSubmission < ApplicationRecord
  belongs_to :form
  belongs_to :contact, optional: true

  validates :payload, presence: true
end
