# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalBudgetSource, type: :model, unit: true do
  let(:email_account) { create(:email_account) }

  describe "associations" do
    it { should belong_to(:user) }

    it "requires email_account" do
      source = build(:external_budget_source, email_account: nil)
      expect(source).not_to be_valid
      expect(source.errors[:email_account]).to be_present
    end

    it "is valid with an email_account" do
      source = build(:external_budget_source, email_account: email_account)
      expect(source).to be_valid
    end
  end

  describe ".for_user scope" do
    let!(:user_a) { create(:user) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:account_b) { create(:email_account, user: user_b) }
    let!(:source_a) { create(:external_budget_source, email_account: account_a, user: user_a) }
    let!(:source_b) { create(:external_budget_source, email_account: account_b, user: user_b) }

    it "returns only records for the given user" do
      expect(ExternalBudgetSource.for_user(user_a)).to include(source_a)
      expect(ExternalBudgetSource.for_user(user_a)).not_to include(source_b)
    end

    it "excludes records from other users" do
      expect(ExternalBudgetSource.for_user(user_b)).to include(source_b)
      expect(ExternalBudgetSource.for_user(user_b)).not_to include(source_a)
    end
  end

  describe "FK forgery guard — email_account_must_belong_to_user" do
    let!(:user_a) { create(:user) }
    let!(:user_b) { create(:user) }
    let!(:account_b) { create(:email_account, user: user_b) }

    it "is invalid when email_account_id belongs to a different user" do
      source = build(:external_budget_source, user: user_a, email_account: account_b)
      expect(source).not_to be_valid
      expect(source.errors[:email_account_id]).to be_present
    end

    it "nullifies email_account_id when the guard fires" do
      source = build(:external_budget_source, user: user_a, email_account: account_b)
      source.valid?
      expect(source.email_account_id).to be_nil
    end

    it "is valid when email_account belongs to the same user" do
      account_a = create(:email_account, user: user_a)
      source = build(:external_budget_source, user: user_a, email_account: account_a)
      expect(source).to be_valid
    end
  end

  describe "source_type validation" do
    it "requires source_type" do
      source = build(:external_budget_source, email_account: email_account, source_type: nil)
      expect(source).not_to be_valid
      expect(source.errors[:source_type]).to be_present
    end

    it "accepts salary_calculator" do
      source = build(:external_budget_source, email_account: email_account, source_type: "salary_calculator")
      expect(source).to be_valid
    end

    it "rejects other values" do
      source = build(:external_budget_source, email_account: email_account, source_type: "other_source")
      expect(source).not_to be_valid
      expect(source.errors[:source_type]).to be_present
    end
  end

  describe "base_url validation" do
    it "requires base_url" do
      source = build(:external_budget_source, email_account: email_account, base_url: nil)
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "rejects non-url string" do
      source = build(:external_budget_source, email_account: email_account, base_url: "not a url")
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "rejects non-http(s) scheme" do
      source = build(:external_budget_source, email_account: email_account, base_url: "ftp://example.com")
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "rejects https:// with no host" do
      source = build(:external_budget_source, email_account: email_account, base_url: "https://")
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "rejects http:// with no host" do
      source = build(:external_budget_source, email_account: email_account, base_url: "http://")
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "rejects https:/// (blank host with trailing path)" do
      source = build(:external_budget_source, email_account: email_account, base_url: "https:///path")
      expect(source).not_to be_valid
      expect(source.errors[:base_url]).to be_present
    end

    it "accepts http://" do
      source = build(:external_budget_source, email_account: email_account, base_url: "http://example.com")
      expect(source).to be_valid
    end

    it "accepts https://" do
      source = build(:external_budget_source, email_account: email_account, base_url: "https://example.com")
      expect(source).to be_valid
    end
  end

  describe "api_token encryption at rest" do
    it "declares api_token as an encrypted attribute" do
      expect(described_class.type_for_attribute(:api_token).class).to be(
        ActiveRecord::Encryption::EncryptedAttributeType
      )
    end

    it "stores ciphertext in the underlying column (not plaintext)" do
      plaintext = "plain-secret-token-xyz"
      source = create(:external_budget_source, email_account: email_account, api_token: plaintext)

      raw_row = ActiveRecord::Base.connection.execute(
        "SELECT api_token FROM external_budget_sources WHERE id = #{source.id.to_i}"
      ).first

      expect(raw_row["api_token"]).not_to eq(plaintext)
      expect(source.reload.api_token).to eq(plaintext)
    end
  end

  describe ".active scope" do
    it "returns only active sources" do
      active_source = create(:external_budget_source)
      inactive_source = create(:external_budget_source, active: false)

      expect(described_class.active).to include(active_source)
      expect(described_class.active).not_to include(inactive_source)
    end
  end

  describe "#record_failure!" do
    let(:source) { create(:external_budget_source, email_account: email_account) }

    it "records failure metadata without deactivating the source" do
      source.record_failure!(error: "401 Unauthorized")

      source.reload
      expect(source.active).to be(true)
      expect(source.last_sync_status).to eq("failed")
      expect(source.last_sync_error).to eq("401 Unauthorized")
    end

    it "truncates long error messages to 1000 characters" do
      long_error = "x" * 1500
      source.record_failure!(error: long_error)

      expect(source.reload.last_sync_error.length).to eq(1000)
    end
  end

  describe "#deactivate!" do
    let(:source) { create(:external_budget_source, email_account: email_account) }

    it "flips active to false and records failure metadata" do
      source.deactivate!(reason: "token revoked")

      source.reload
      expect(source.active).to be(false)
      expect(source.last_sync_status).to eq("failed")
      expect(source.last_sync_error).to eq("token revoked")
    end

    it "truncates long reason messages to 1000 characters" do
      long_reason = "x" * 1500
      source.deactivate!(reason: long_reason)

      expect(source.reload.last_sync_error.length).to eq(1000)
    end
  end

  it "does not expose the removed #mark_failed! method" do
    source = create(:external_budget_source, email_account: email_account)
    expect(source).not_to respond_to(:mark_failed!)
  end

  describe "#mark_succeeded!" do
    let(:source) do
      create(:external_budget_source, email_account: email_account,
                                      last_sync_status: "failed",
                                      last_sync_error: "prior failure")
    end

    it "records success metadata and clears prior error" do
      freeze_time = Time.current
      travel_to(freeze_time) do
        source.mark_succeeded!
      end

      source.reload
      expect(source.last_synced_at).to be_within(1.second).of(freeze_time)
      expect(source.last_sync_status).to eq("ok")
      expect(source.last_sync_error).to be_nil
    end
  end

  describe "one-per-email_account uniqueness" do
    it "raises when attempting a second source for the same email_account" do
      create(:external_budget_source, email_account: email_account)

      expect {
        create(:external_budget_source, email_account: email_account)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
