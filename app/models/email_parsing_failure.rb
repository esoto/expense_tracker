class EmailParsingFailure < ApplicationRecord
  belongs_to :email_account

  validates :error_messages, presence: true
end
