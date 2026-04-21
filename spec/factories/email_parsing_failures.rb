FactoryBot.define do
  factory :email_parsing_failure do
    association :email_account
    user { email_account&.user || association(:user) }
    bank_name { "BAC" }
    error_messages { [ "Amount not found" ] }
    raw_email_content { "Unparseable email content" }
    original_email_size { 25 }
    truncated { false }
  end
end
