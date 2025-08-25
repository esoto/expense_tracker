# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSessionAccount, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_sync_session_account(attributes = {})
    default_attributes = {
      status: "pending",
      processed_emails: 0,
      total_emails: 0,
      detected_expenses: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:sync_session_account, default_attributes.merge(attributes))
  end

  describe "associations" do
    it { should belong_to(:sync_session) }
    it { should belong_to(:email_account) }
  end

  describe "validations" do
    describe "status" do
      it "requires status to be present" do
        account = build_sync_session_account(status: nil)
        expect(account).not_to be_valid
        expect(account.errors[:status]).to include("can't be blank")
      end

      it "validates inclusion in allowed values" do
        valid_statuses = %w[pending waiting processing completed failed]
        valid_statuses.each do |status|
          account = build_sync_session_account(status: status)
          expect(account).to be_valid
        end
      end

      it "rejects invalid status values" do
        account = build_sync_session_account(status: "invalid")
        expect(account).not_to be_valid
        expect(account.errors[:status]).to include("is not included in the list")
      end
    end
  end

  describe "scopes" do
    describe ".active" do
      it "filters by processing status" do
        result = SyncSessionAccount.active
        expect(result.where_values_hash["status"]).to eq("processing")
      end
    end

    describe ".completed" do
      it "filters by completed status" do
        result = SyncSessionAccount.completed
        expect(result.where_values_hash["status"]).to eq("completed")
      end
    end

    describe ".failed" do
      it "filters by failed status" do
        result = SyncSessionAccount.failed
        expect(result.where_values_hash["status"]).to eq("failed")
      end
    end
  end

  describe "#progress_percentage" do
    context "with emails to process" do
      it "calculates percentage correctly" do
        account = build_sync_session_account(processed_emails: 25, total_emails: 100)
        expect(account.progress_percentage).to eq(25)
      end

      it "rounds to nearest integer" do
        account = build_sync_session_account(processed_emails: 33, total_emails: 100)
        expect(account.progress_percentage).to eq(33)
      end

      it "handles completed processing" do
        account = build_sync_session_account(processed_emails: 100, total_emails: 100)
        expect(account.progress_percentage).to eq(100)
      end
    end

    context "with zero total emails" do
      it "returns 0" do
        account = build_sync_session_account(processed_emails: 0, total_emails: 0)
        expect(account.progress_percentage).to eq(0)
      end
    end
  end

  describe "status check methods" do
    describe "#processing?" do
      it "returns true when status is processing" do
        account = build_sync_session_account(status: "processing")
        expect(account.processing?).to be true
      end

      it "returns false for other statuses" do
        %w[pending waiting completed failed].each do |status|
          account = build_sync_session_account(status: status)
          expect(account.processing?).to be false
        end
      end
    end

    describe "#completed?" do
      it "returns true when status is completed" do
        account = build_sync_session_account(status: "completed")
        expect(account.completed?).to be true
      end

      it "returns false for other statuses" do
        %w[pending waiting processing failed].each do |status|
          account = build_sync_session_account(status: status)
          expect(account.completed?).to be false
        end
      end
    end

    describe "#failed?" do
      it "returns true when status is failed" do
        account = build_sync_session_account(status: "failed")
        expect(account.failed?).to be true
      end

      it "returns false for other statuses" do
        %w[pending waiting processing completed].each do |status|
          account = build_sync_session_account(status: status)
          expect(account.failed?).to be false
        end
      end
    end

    describe "#pending?" do
      it "returns true when status is pending" do
        account = build_sync_session_account(status: "pending")
        expect(account.pending?).to be true
      end

      it "returns false for other statuses" do
        %w[waiting processing completed failed].each do |status|
          account = build_sync_session_account(status: status)
          expect(account.pending?).to be false
        end
      end
    end

    describe "#waiting?" do
      it "returns true when status is waiting" do
        account = build_sync_session_account(status: "waiting")
        expect(account.waiting?).to be true
      end

      it "returns false for other statuses" do
        %w[pending processing completed failed].each do |status|
          account = build_sync_session_account(status: status)
          expect(account.waiting?).to be false
        end
      end
    end
  end

  describe "#start_processing!" do
    let(:account) { build_sync_session_account(status: "pending") }

    it "updates status to processing" do
      expect(account).to receive(:update!).with(status: "processing")
      account.start_processing!
    end
  end

  describe "#complete!" do
    let(:account) { build_sync_session_account(status: "processing") }
    let(:sync_session) { build_stubbed(:sync_session) }

    before do
      allow(account).to receive(:sync_session).and_return(sync_session)
      allow(account).to receive(:update!)
      allow(sync_session).to receive(:update_progress)
    end

    it "updates status to completed" do
      expect(account).to receive(:update!).with(status: "completed")
      account.complete!
    end

    it "updates parent session progress" do
      expect(sync_session).to receive(:update_progress)
      account.complete!
    end
  end

  describe "#fail!" do
    let(:account) { build_sync_session_account(status: "processing") }

    it "updates status to failed with error message" do
      expect(account).to receive(:update!).with(status: "failed", last_error: "Connection timeout")
      account.fail!("Connection timeout")
    end

    it "updates status to failed without error message" do
      expect(account).to receive(:update!).with(status: "failed", last_error: nil)
      account.fail!
    end
  end

  describe "#update_progress" do
    let(:account) do
      build_sync_session_account(
        processed_emails: 10,
        total_emails: 50,
        detected_expenses: 5
      )
    end
    let(:sync_session) { build_stubbed(:sync_session) }

    before do
      allow(account).to receive(:sync_session).and_return(sync_session)
      allow(account).to receive(:update_columns)
      allow(sync_session).to receive(:update_progress)
    end

    it "updates progress columns" do
      freeze_time do
        expect(account).to receive(:update_columns).with(
          processed_emails: 20,
          total_emails: 50,
          detected_expenses: 8,
          updated_at: Time.current
        )
        account.update_progress(20, 50, 3)
      end
    end

    it "updates parent session progress" do
      expect(sync_session).to receive(:update_progress)
      account.update_progress(20, 50, 3)
    end

    context "with ActiveRecord::StaleObjectError" do
      before do
        call_count = 0
        allow(account).to receive(:update_columns) do
          call_count += 1
          raise ActiveRecord::StaleObjectError if call_count == 1
        end
        allow(account).to receive(:reload)
      end

      it "retries on stale object error" do
        expect(account).to receive(:reload)
        expect(account).to receive(:update_columns).twice
        account.update_progress(20, 50, 3)
      end
    end
  end

  describe "edge cases" do
    describe "progress calculation" do
      it "handles overflow in processed emails" do
        account = build_sync_session_account(processed_emails: 150, total_emails: 100)
        expect(account.progress_percentage).to eq(150)
      end

      it "handles negative values" do
        account = build_sync_session_account(processed_emails: -10, total_emails: 100)
        expect(account.progress_percentage).to eq(-10)
      end

      it "handles very large numbers" do
        account = build_sync_session_account(processed_emails: 1_000_000, total_emails: 10_000_000)
        expect(account.progress_percentage).to eq(10)
      end
    end

    describe "concurrent updates" do
      let(:account) { build_sync_session_account }
      let(:sync_session) { build_stubbed(:sync_session) }

      before do
        allow(account).to receive(:sync_session).and_return(sync_session)
        allow(sync_session).to receive(:update_progress)
      end

      it "uses update_columns to avoid locking issues" do
        expect(account).to receive(:update_columns).with(hash_including(:processed_emails))
        account.update_progress(10, 20, 5)
      end
    end

    describe "error handling" do
      it "preserves error messages in fail!" do
        account = build_sync_session_account
        error_msg = "A" * 1000  # Very long error message
        expect(account).to receive(:update!).with(status: "failed", last_error: error_msg)
        account.fail!(error_msg)
      end
    end
  end
end
