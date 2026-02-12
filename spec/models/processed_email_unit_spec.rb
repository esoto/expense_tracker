# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessedEmail, type: :model, unit: true do
  # # Helper method to build a stubbed instance
  # def build_processed_email(attributes = {})
  #   default_attributes = {
  #     message_id: "msg_123@example.com",
  #     processed_at: Time.current,
  #     created_at: Time.current,
  #     updated_at: Time.current
  #   }
  #   build_stubbed(:processed_email, default_attributes.merge(attributes))
  # end

  describe "associations" do
    it { should belong_to(:email_account) }
  end

  describe "validations" do
    subject { build(:processed_email) }

    it { should validate_presence_of(:message_id) }
    it { should validate_uniqueness_of(:message_id).scoped_to(:email_account_id) }
    it { should validate_presence_of(:email_account) }
  end

  describe "scopes" do
    describe ".for_account" do
      it "filters by email account" do
        account = build(:email_account)
        result = ProcessedEmail.for_account(account)
        expect(result.where_values_hash["email_account_id"]).to eq(account.id)
      end
    end

    describe ".recent" do
      it "orders by processed_at descending" do
        sql = ProcessedEmail.recent.to_sql
        expect(sql).to include("ORDER BY")
        expect(sql).to include("processed_at\" DESC")
      end
    end

    describe ".by_date_range" do
      it "filters by date range" do
        start_date = Date.new(2024, 1, 1)
        end_date = Date.new(2024, 1, 31)

        # The actual SQL will contain a BETWEEN clause or similar
        result = ProcessedEmail.by_date_range(start_date, end_date)
        expect(result.to_sql).to include("processed_at")
      end
    end
  end

  describe ".already_processed?" do
    let(:account) { create(:email_account) }
    let(:message_id) { "msg_123" }

    context "when email already processed" do
      before do
        create(:processed_email, message_id: message_id, email_account: account)
      end
      it "returns true" do
        expect(ProcessedEmail.already_processed?(message_id, account)).to be true
      end
    end

    context "when email not processed" do
      it "returns false" do
        expect(ProcessedEmail.already_processed?(message_id, account)).to be false
      end
    end
  end
end
