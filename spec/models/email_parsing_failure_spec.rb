require 'rails_helper'

RSpec.describe EmailParsingFailure, type: :model, unit: true do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:email_account) }
  end

  describe 'validations' do
    it 'allows empty error_messages array' do
      failure = build(:email_parsing_failure, error_messages: [])
      expect(failure).to be_valid
    end

    it 'rejects nil error_messages' do
      failure = build(:email_parsing_failure, error_messages: nil)
      expect(failure).not_to be_valid
    end
  end

  describe 'defaults' do
    subject(:failure) { described_class.new }

    it 'defaults error_messages to empty array' do
      expect(failure.error_messages).to eq([])
    end

    it 'defaults truncated to false' do
      expect(failure.truncated).to eq(false)
    end
  end

  describe 'factory' do
    it 'creates a valid record' do
      failure = build(:email_parsing_failure)
      expect(failure).to be_valid
    end
  end

  describe 'dependent destroy from email_account' do
    it 'is destroyed when email_account is destroyed' do
      failure = create(:email_parsing_failure)
      email_account = failure.email_account

      expect { email_account.destroy }.to change(described_class, :count).by(-1)
    end
  end

  # PER-496: raw_email_content contains bank PII (amounts, merchants, account
  # refs, transaction times) — must be encrypted at rest.
  describe 'encryption' do
    it 'encrypts raw_email_content at rest' do
      expect(described_class.type_for_attribute(:raw_email_content).class).to be(
        ActiveRecord::Encryption::EncryptedAttributeType
      )
    end

    it 'round-trips plaintext through encrypt/decrypt transparently' do
      failure = create(:email_parsing_failure, raw_email_content: "BAC statement: $123.45 to MERCHANT")
      failure.reload
      expect(failure.raw_email_content).to eq("BAC statement: $123.45 to MERCHANT")
    end

    it 'stores ciphertext in the underlying column (not plaintext)' do
      plaintext = "sensitive bank content #{SecureRandom.hex(8)}"
      create(:email_parsing_failure, raw_email_content: plaintext)

      raw_row = ActiveRecord::Base.connection.execute(
        "SELECT raw_email_content FROM email_parsing_failures ORDER BY id DESC LIMIT 1"
      ).first
      expect(raw_row["raw_email_content"]).not_to include(plaintext)
    end

    # support_unencrypted_data allows the 30-day retention window to age out
    # any rows that were written as plaintext before this PR.
    # update_all bypasses the encrypt writer (same effect as pre-PR legacy
    # rows) without raw SQL string interpolation.
    it 'still reads existing plaintext rows during the retention window' do
      failure = create(:email_parsing_failure)
      described_class.where(id: failure.id).update_all(raw_email_content: 'legacy plaintext')

      expect(failure.reload.raw_email_content).to eq('legacy plaintext')
    end
  end

  # PR 7 — user_id association and scoping
  describe 'user ownership (PR 7)' do
    describe '.for_user scope' do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }
      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }
      let!(:failure_a) { create(:email_parsing_failure, email_account: account_a, user: user_a) }
      let!(:failure_b) { create(:email_parsing_failure, email_account: account_b, user: user_b) }

      it 'returns only failures belonging to user_a' do
        result = EmailParsingFailure.for_user(user_a)
        expect(result).to include(failure_a)
        expect(result).not_to include(failure_b)
      end

      it 'returns only failures belonging to user_b' do
        result = EmailParsingFailure.for_user(user_b)
        expect(result).to include(failure_b)
        expect(result).not_to include(failure_a)
      end

      it 'returns an empty relation when user has no failures' do
        user_c = create(:user)
        expect(EmailParsingFailure.for_user(user_c)).to be_empty
      end
    end
  end
end
