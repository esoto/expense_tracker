# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::BulkOperations::StatusUpdateService, type: :service, unit: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let!(:expenses) do
    create_list(:expense, 3, email_account: email_account, category: category, status: "pending")
  end
  let(:expense_ids) { expenses.map(&:id) }

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  describe "validation" do
    describe "status presence validation" do
      it "is invalid when status is nil" do
        service = described_class.new(expense_ids: expense_ids, status: nil)
        expect(service).not_to be_valid
        expect(service.errors[:status]).to be_present
      end

      it "is invalid when status is blank string" do
        service = described_class.new(expense_ids: expense_ids, status: "")
        expect(service).not_to be_valid
        expect(service.errors[:status]).to be_present
      end
    end

    describe "status inclusion validation" do
      it "is invalid when status is not in VALID_STATUSES" do
        service = described_class.new(expense_ids: expense_ids, status: "invalid_status")
        expect(service).not_to be_valid
        expect(service.errors[:status]).to be_present
      end

      it "is invalid when status is a misspelled valid status" do
        service = described_class.new(expense_ids: expense_ids, status: "proceesed")
        expect(service).not_to be_valid
        expect(service.errors[:status]).to be_present
      end
    end

    describe "valid statuses" do
      described_class::VALID_STATUSES.each do |valid_status|
        it "is valid when status is '#{valid_status}'" do
          service = described_class.new(expense_ids: expense_ids, status: valid_status)
          service.valid?
          expect(service.errors[:status]).to be_empty
        end
      end
    end

    it "validates status inclusion in VALID_STATUSES constant" do
      expect(described_class::VALID_STATUSES).to eq(%w[pending processed failed duplicate])
    end

    it "has status attribute accessible" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      expect(service.status).to eq("processed")
    end
  end

  # ---------------------------------------------------------------------------
  # #initialize
  # ---------------------------------------------------------------------------

  describe "#initialize" do
    it "sets expense_ids" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      expect(service.expense_ids).to eq(expense_ids)
    end

    it "sets status" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      expect(service.status).to eq("processed")
    end

    it "sets user when provided" do
      user = double("User", id: 1)
      service = described_class.new(expense_ids: expense_ids, status: "processed", user: user)
      expect(service.user).to eq(user)
    end

    it "defaults user to nil when not provided" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      expect(service.user).to be_nil
    end

    it "sets options when provided" do
      opts = { broadcast_updates: true }
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: opts
      )
      expect(service.options).to eq(opts)
    end

    it "defaults options to empty hash when not provided" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      expect(service.options).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # #call — basic happy path
  # ---------------------------------------------------------------------------

  describe "#call" do
    context "happy path — all expenses found and updated" do
      it "updates all expenses to the new status" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:success]).to be true
        expenses.each { |e| expect(e.reload.status).to eq("processed") }
      end

      it "returns success: true" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:success]).to be true
      end

      it "returns correct affected_count" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:affected_count]).to eq(3)
      end

      it "returns Spanish success message" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:message]).to eq("3 gastos actualizados exitosamente")
      end

      it "updates updated_at timestamp" do
        before_time = Time.current
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        service.call

        expenses.each do |expense|
          expect(expense.reload.updated_at).to be >= before_time
        end
      end

      it "works with all valid statuses" do
        described_class::VALID_STATUSES.each do |status|
          expense = create(:expense, email_account: email_account, category: category)

          service = described_class.new(
            expense_ids: [ expense.id ],
            status: status,
            options: { force_synchronous: true }
          )
          result = service.call

          expect(result[:success]).to be true
          expect(expense.reload.status).to eq(status)
        end
      end
    end

    context "validation failures" do
      it "returns failure when status is invalid" do
        service = described_class.new(expense_ids: expense_ids, status: "bogus")
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end

      it "returns failure when status is nil" do
        service = described_class.new(expense_ids: expense_ids, status: nil)
        result = service.call

        expect(result[:success]).to be false
      end
    end

    context "missing expenses" do
      it "returns failure when some expenses don't exist" do
        fake_id = 999_999
        service = described_class.new(
          expense_ids: expense_ids + [ fake_id ],
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found or unauthorized")
      end

      it "returns failure when no expenses exist" do
        service = described_class.new(
          expense_ids: [999_999, 999_998],
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:success]).to be false
      end

      it "does not update any expenses when some are missing" do
        original_status = expenses.first.status
        fake_id = 999_999
        service = described_class.new(
          expense_ids: expense_ids + [fake_id],
          status: "processed",
          options: { force_synchronous: true }
        )
        service.call

        expect(expenses.first.reload.status).to eq(original_status)
      end
    end

    context "empty expense_ids" do
      it "returns failure when expense_ids is empty" do
        service = described_class.new(expense_ids: [], status: "processed")
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Expense ids no puede estar en blanco")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #perform_operation — batch update with fallback
  # ---------------------------------------------------------------------------

  describe "perform_operation" do
    context "batch update with update_all" do
      it "updates all expenses in a single query" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )

        expect_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_call_original
        service.call
      end

      it "returns success_count in the result" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        service.call

        expenses.each { |e| expect(e.reload.status).to eq("processed") }
      end

      it "returns empty failures array when all succeed" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )
        result = service.call

        expect(result[:failures]).to be_empty
      end
    end

    context "fallback to individual updates when batch fails" do
      it "falls back to individual updates when update_all raises" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )

        # Mock update_all to fail on first relation
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(StandardError.new("batch write failed"))

        result = service.call

        # Fallback should succeed via individual updates
        expect(result[:success]).to be true
        expenses.each { |e| expect(e.reload.status).to eq("processed") }
      end

      it "falls back gracefully when batch update fails with database error" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )

        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(PG::Error.new("connection lost"))

        result = service.call

        expect(result[:success]).to be true
        expenses.each { |e| expect(e.reload.status).to eq("processed") }
      end

      it "returns success_count in fallback path" do
        service = described_class.new(
          expense_ids: expense_ids,
          status: "processed",
          options: { force_synchronous: true }
        )

        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(StandardError.new("failed"))

        result = service.call

        expect(result[:affected_count]).to eq(3)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #broadcast_status_updates
  # ---------------------------------------------------------------------------

  describe "broadcast_status_updates" do
    it "broadcasts when broadcast_updates option is set to true" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      expect(ActionCable.server).to receive(:broadcast).at_least(3).times
      service.call
    end

    it "broadcasts one message per expense" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      expect(ActionCable.server).to receive(:broadcast).exactly(3).times
      service.call
    end

    it "broadcasts with correct channel name" do
      service = described_class.new(
        expense_ids: [expenses.first.id],
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "expenses_#{email_account.id}",
        hash_including(:action, :expense_id, :status)
      )

      service.call
    end

    it "broadcasts with correct payload structure" do
      expense = expenses.first
      service = described_class.new(
        expense_ids: [expense.id],
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "expenses_#{email_account.id}",
        {
          action: "status_updated",
          expense_id: expense.id,
          status: "processed"
        }
      )

      service.call
    end

    it "does not broadcast when broadcast_updates option is not set" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      expect(ActionCable.server).not_to receive(:broadcast)
      service.call
    end

    it "does not broadcast when broadcast_updates is false" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { broadcast_updates: false, force_synchronous: true }
      )

      expect(ActionCable.server).not_to receive(:broadcast)
      service.call
    end

    it "does not fail the operation if broadcast raises" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      allow(ActionCable.server).to receive(:broadcast)
        .and_raise(StandardError.new("cable connection lost"))

      result = service.call

      expect(result[:success]).to be true
      expenses.each { |e| expect(e.reload.status).to eq("processed") }
    end

    it "logs broadcast failure without failing the operation" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      allow(ActionCable.server).to receive(:broadcast)
        .and_raise(StandardError.new("broadcast failed"))

      expect(Rails.logger).to receive(:warn).with(/Failed to broadcast status updates/)

      service.call
    end

    it "broadcasts to multiple channels when expenses span email accounts" do
      other_account = create(:email_account)
      other_expense = create(:expense, email_account: other_account, category: category)
      mixed_ids = expense_ids + [other_expense.id]

      service = described_class.new(
        expense_ids: mixed_ids,
        status: "processed",
        options: { broadcast_updates: true, force_synchronous: true }
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        "expenses_#{email_account.id}",
        anything
      ).at_least(3).times

      expect(ActionCable.server).to receive(:broadcast).with(
        "expenses_#{other_account.id}",
        anything
      ).at_least(1).times

      service.call
    end
  end

  # ---------------------------------------------------------------------------
  # #success_message
  # ---------------------------------------------------------------------------

  describe "#success_message" do
    it "returns Spanish success message with count" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      message = service.send(:success_message, 5)

      expect(message).to eq("5 gastos actualizados exitosamente")
    end

    it "returns message for single expense" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      message = service.send(:success_message, 1)

      expect(message).to eq("1 gastos actualizados exitosamente")
    end

    it "returns message for zero expenses" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      message = service.send(:success_message, 0)

      expect(message).to eq("0 gastos actualizados exitosamente")
    end

    it "returns message for large count" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")
      message = service.send(:success_message, 1000)

      expect(message).to eq("1000 gastos actualizados exitosamente")
    end

    it "always uses 'gastos actualizados exitosamente' regardless of status" do
      described_class::VALID_STATUSES.each do |status|
        service = described_class.new(expense_ids: expense_ids, status: status)
        message = service.send(:success_message, 10)

        expect(message).to eq("10 gastos actualizados exitosamente")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #background_job_class
  # ---------------------------------------------------------------------------

  describe "#background_job_class" do
    it "returns BulkStatusUpdateJob" do
      service = described_class.new(expense_ids: expense_ids, status: "processed")

      expect(service.send(:background_job_class)).to eq(BulkStatusUpdateJob)
    end
  end

  # ---------------------------------------------------------------------------
  # Individual updates fallback path
  # ---------------------------------------------------------------------------

  describe "#perform_individual_updates (fallback)" do
    it "updates expenses one by one when batch fails" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
        .and_raise(StandardError.new("batch failed"))

      service.call

      expenses.each { |e| expect(e.reload.status).to eq("processed") }
    end

    it "returns failures array when individual updates fail" do
      expense = expenses.first
      service = described_class.new(
        expense_ids: [expense.id],
        status: "processed",
        options: { force_synchronous: true }
      )

      # Mock an individual update to fail
      allow_any_instance_of(Expense).to receive(:update).and_return(false)
      allow_any_instance_of(Expense).to receive(:errors).and_return(
        double(full_messages: ["Status is invalid"])
      )

      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
        .and_raise(StandardError.new("batch failed"))

      allow_any_instance_of(ActiveRecord::Relation).to receive(:find_each).and_yield(expense)

      result = service.call

      expect(result[:failures]).to be_an(Array)
    end

    it "continues updating other expenses even if one fails" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
        .and_raise(StandardError.new("batch failed"))

      result = service.call

      # All expenses should be updated despite individual failures
      expect(result[:success]).to be true
      expenses.each { |e| expect(e.reload.status).to eq("processed") }
    end
  end

  # ---------------------------------------------------------------------------
  # Synchronous vs background processing
  # ---------------------------------------------------------------------------

  describe "synchronous vs background processing" do
    it "processes synchronously when below BACKGROUND_THRESHOLD" do
      small_ids = expense_ids
      service = described_class.new(
        expense_ids: small_ids,
        status: "processed"
      )

      expect(service).to receive(:process_synchronously).and_call_original

      service.call
    end

    it "enqueues background job when at BACKGROUND_THRESHOLD" do
      threshold = Services::BulkOperations::BaseService::BACKGROUND_THRESHOLD
      large_ids = Array.new(threshold) { |i| i + 1 }

      service = described_class.new(
        expense_ids: large_ids,
        status: "processed"
      )

      allow(BulkStatusUpdateJob).to receive(:perform_later).and_return(
        double(job_id: "job-123")
      )

      result = service.call

      expect(result[:success]).to be true
      expect(result[:background]).to be true
    end

    it "forces synchronous even above threshold when option is set" do
      threshold = Services::BulkOperations::BaseService::BACKGROUND_THRESHOLD
      large_ids = Array.new(threshold + 10) { create(:expense, email_account: email_account, category: category).id }

      service = described_class.new(
        expense_ids: large_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      result = service.call

      expect(result[:success]).to be true
      expect(result[:background]).not_to eq(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "integration scenarios" do
    it "updates expenses of different statuses to new status" do
      expense1 = create(:expense, email_account: email_account, category: category, status: "pending")
      expense2 = create(:expense, email_account: email_account, category: category, status: "processed")
      expense3 = create(:expense, email_account: email_account, category: category, status: "failed")

      service = described_class.new(
        expense_ids: [expense1.id, expense2.id, expense3.id],
        status: "duplicate",
        options: { force_synchronous: true }
      )

      result = service.call

      expect(result[:success]).to be true
      expect(expense1.reload.status).to eq("duplicate")
      expect(expense2.reload.status).to eq("duplicate")
      expect(expense3.reload.status).to eq("duplicate")
    end

    it "handles update_all returning partial count correctly" do
      service = described_class.new(
        expense_ids: expense_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      # Simulate update_all returning actual count
      result = service.call

      expect(result[:affected_count]).to eq(3)
    end

    it "works with single expense" do
      expense = expenses.first
      service = described_class.new(
        expense_ids: [expense.id],
        status: "processed",
        options: { force_synchronous: true }
      )

      result = service.call

      expect(result[:success]).to be true
      expect(result[:affected_count]).to eq(1)
      expect(expense.reload.status).to eq("processed")
    end

    it "works with large number of expenses" do
      large_expense_list = create_list(
        :expense,
        50,
        email_account: email_account,
        category: category,
        status: "pending"
      )
      large_ids = large_expense_list.map(&:id)

      service = described_class.new(
        expense_ids: large_ids,
        status: "processed",
        options: { force_synchronous: true }
      )

      result = service.call

      expect(result[:success]).to be true
      expect(result[:affected_count]).to eq(50)
      large_expense_list.each { |e| expect(e.reload.status).to eq("processed") }
    end
  end

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  describe "constants" do
    it "defines VALID_STATUSES" do
      expect(described_class.const_defined?(:VALID_STATUSES)).to be true
    end

    it "VALID_STATUSES is frozen" do
      expect(described_class::VALID_STATUSES).to be_frozen
    end

    it "VALID_STATUSES contains expected values" do
      expect(described_class::VALID_STATUSES).to include("pending", "processed", "failed", "duplicate")
    end
  end
end
