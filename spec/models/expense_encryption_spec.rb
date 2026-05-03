# frozen_string_literal: true

require "rails_helper"

# PER-533: raw_email_content contains bank PII (amounts, merchants, account
# refs, transaction times) — must be encrypted at rest, matching PER-496 for
# EmailParsingFailure.
RSpec.describe Expense, :unit, type: :model do
  describe "encryption of raw_email_content" do
    it "declares raw_email_content as an encrypted attribute" do
      expect(described_class.type_for_attribute(:raw_email_content).class).to be(
        ActiveRecord::Encryption::EncryptedAttributeType
      )
    end

    it "round-trips plaintext through encrypt/decrypt transparently" do
      expense = create(:expense, :with_raw_email,
                       raw_email_content: "BAC: Cargo por ₡12345.67 a SUPERMERCADO")
      expense.reload
      expect(expense.raw_email_content).to eq("BAC: Cargo por ₡12345.67 a SUPERMERCADO")
    end

    it "stores ciphertext in the underlying column (not plaintext)" do
      plaintext = "sensitive bank content #{SecureRandom.hex(8)}"
      expense = create(:expense, :with_raw_email, raw_email_content: plaintext)

      raw_row = ActiveRecord::Base.connection.execute(
        "SELECT raw_email_content FROM expenses WHERE id = #{expense.id}"
      ).first
      expect(raw_row["raw_email_content"]).not_to include(plaintext)
      expect(raw_row["raw_email_content"]).to be_present
    end

    # support_unencrypted_data: true keeps legacy plaintext rows readable while
    # the backfill runs. Raw SQL bypasses the AR Encryption layer, simulating
    # a row written to the database before the encrypts declaration was deployed.
    it "reads existing plaintext rows via support_unencrypted_data: true" do
      expense = create(:expense, :with_raw_email)
      ActiveRecord::Base.connection.execute(
        "UPDATE expenses SET raw_email_content = 'legacy plaintext body' WHERE id = #{expense.id}"
      )

      expect(expense.reload.raw_email_content).to eq("legacy plaintext body")
    end

    # MonitoringService#email_processing_metrics (line 781) queries:
    #   Expense.where(...).where.not(raw_email_content: nil).count
    # Non-deterministic encryption writes non-null ciphertext, so this presence
    # check must still return a truthy count after encryption.
    it "presence query .where.not(raw_email_content: nil) still counts encrypted rows" do
      email_account = create(:email_account)
      user = email_account.user

      # Create two expenses — one with content, one without
      create(:expense, email_account:, user:, raw_email_content: "bank email body #{SecureRandom.hex}")
      create(:expense, email_account:, user:, raw_email_content: nil)

      count = described_class
                .where(user_id: user.id)
                .where.not(raw_email_content: nil)
                .count

      expect(count).to eq(1)
    end
  end
end
