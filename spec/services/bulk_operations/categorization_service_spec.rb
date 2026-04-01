# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::BulkOperations::CategorizationService, type: :service, unit: true do
  let(:email_account) { create(:email_account) }
  let(:other_email_account) { create(:email_account) }
  let(:target_category) { create(:category) }
  let(:other_category) { create(:category) }
  let!(:expenses) { create_list(:expense, 3, email_account: email_account, category: other_category) }
  let(:expense_ids) { expenses.map(&:id) }

  # ---------------------------------------------------------------------------
  # Initialization
  # ---------------------------------------------------------------------------

  describe "#initialize" do
    it "sets category_id", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)

      expect(service.category_id).to eq(target_category.id)
    end

    it "delegates expense_ids, user, and options to base", unit: true do
      user = double("User", id: 1)
      opts = { broadcast_updates: false }
      service = described_class.new(
        expense_ids: expense_ids,
        category_id: target_category.id,
        user: user,
        options: opts
      )

      expect(service.expense_ids).to eq(expense_ids)
      expect(service.user).to eq(user)
      expect(service.options).to eq(opts)
    end

    it "initializes results with default values", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)

      expect(service.results).to include(
        success: false,
        affected_count: 0,
        failures: [],
        errors: [],
        message: nil
      )
    end

    it "accepts nil user", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id, user: nil)
      expect(service.user).to be_nil
    end

    it "defaults options to empty hash", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)
      expect(service.options).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  describe "validations" do
    context "when category_id is blank", unit: true do
      let(:service) { described_class.new(expense_ids: expense_ids, category_id: nil) }

      it "returns a failed result", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end

      it "includes a presence error on category_id", unit: true do
        service.valid?
        expect(service.errors[:category_id]).to be_present
      end
    end

    context "when category_id does not exist", unit: true do
      let(:service) { described_class.new(expense_ids: expense_ids, category_id: 999_999) }

      it "returns a failed result stating category does not exist", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(service.errors[:category_id]).to be_present
      end
    end

    context "when expense_ids is nil", unit: true do
      let(:service) { described_class.new(expense_ids: nil, category_id: target_category.id) }

      it "returns a failed result", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end

      it "does not attempt database queries", unit: true do
        expect(Expense).not_to receive(:where)
        service.call
      end
    end

    context "when expense_ids is not an array", unit: true do
      let(:service) { described_class.new(expense_ids: "123", category_id: target_category.id) }

      it "returns a failed result with array error", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Expense ids must be an array")
      end
    end

    context "when expense_ids is empty", unit: true do
      let(:service) { described_class.new(expense_ids: [], category_id: target_category.id) }

      it "returns a failed result", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end

    context "when both expense_ids and category_id are invalid", unit: true do
      let(:service) { described_class.new(expense_ids: nil, category_id: nil) }

      it "returns multiple validation errors", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors].size).to be >= 2
      end
    end
  end

  # ---------------------------------------------------------------------------
  # perform_operation — batch update via update_all
  # ---------------------------------------------------------------------------

  describe "#call — perform_operation (update_all)", unit: true do
    let(:service) do
      described_class.new(
        expense_ids: expense_ids,
        category_id: target_category.id,
        options: { force_synchronous: true }
      )
    end

    it "returns success: true" do
      result = service.call

      expect(result[:success]).to be true
    end

    it "returns the correct affected_count" do
      result = service.call

      expect(result[:affected_count]).to eq(3)
    end

    it "sets category_id on every expense via update_all" do
      service.call

      expenses.each(&:reload)
      expect(expenses.map(&:category_id)).to all(eq(target_category.id))
    end

    it "updates updated_at on every expense" do
      before_call = Time.current - 1.second
      service.call

      expenses.each do |expense|
        expect(expense.reload.updated_at).to be >= before_call
      end
    end

    it "returns zero failures" do
      result = service.call

      expect(result[:failures]).to be_empty
    end

    it "does not modify expenses outside the given IDs" do
      other_expenses = create_list(:expense, 2, email_account: other_email_account, category: nil)
      service.call

      other_expenses.each do |expense|
        expect(expense.reload.category_id).to be_nil
      end
    end

    it "overwrites an existing category on each expense" do
      service.call

      expenses.each do |expense|
        expect(expense.reload.category_id).to eq(target_category.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ML correction tracking
  # ---------------------------------------------------------------------------

  describe "#call — ML correction tracking" do
    let(:ml_category) { create(:category) }

    context "when track_ml_corrections is true", unit: true do
      let!(:expense_different_suggestion) do
        create(:expense,
          email_account: email_account,
          category: other_category,
          ml_suggested_category_id: ml_category.id,
          ml_correction_count: 0)
      end
      let!(:expense_same_suggestion) do
        create(:expense,
          email_account: email_account,
          category: other_category,
          ml_suggested_category_id: target_category.id,
          ml_correction_count: 0)
      end
      let!(:expense_no_suggestion) do
        create(:expense,
          email_account: email_account,
          category: other_category,
          ml_suggested_category_id: nil,
          ml_correction_count: 0)
      end
      let(:service) do
        described_class.new(
          expense_ids: [
            expense_different_suggestion.id,
            expense_same_suggestion.id,
            expense_no_suggestion.id
          ],
          category_id: target_category.id,
          options: { track_ml_corrections: true, force_synchronous: true }
        )
      end

      it "increments ml_correction_count when suggestion differs from chosen category" do
        service.call

        expect(expense_different_suggestion.reload.ml_correction_count).to eq(1)
      end

      it "does not increment ml_correction_count when suggestion matches chosen category" do
        service.call

        expect(expense_same_suggestion.reload.ml_correction_count).to eq(0)
      end

      it "does not increment ml_correction_count for expenses with no ML suggestion" do
        service.call

        expect(expense_no_suggestion.reload.ml_correction_count).to eq(0)
      end

      it "sets ml_last_corrected_at for corrected expenses" do
        before_call = Time.current - 1.second
        service.call

        expect(expense_different_suggestion.reload.ml_last_corrected_at).to be >= before_call
      end

      it "does not set ml_last_corrected_at when suggestion matches chosen category" do
        service.call

        expect(expense_same_suggestion.reload.ml_last_corrected_at).to be_nil
      end

      it "clears ml_suggested_category_id when suggestion differs from chosen category" do
        service.call

        expect(expense_different_suggestion.reload.ml_suggested_category_id).to be_nil
      end

      it "preserves ml_suggested_category_id when suggestion matches chosen category" do
        service.call

        expect(expense_same_suggestion.reload.ml_suggested_category_id).to eq(target_category.id)
      end

      it "leaves ml_suggested_category_id nil for expenses with no suggestion" do
        service.call

        expect(expense_no_suggestion.reload.ml_suggested_category_id).to be_nil
      end

      it "accumulates ml_correction_count across multiple calls" do
        service.call
        expense = expense_different_suggestion.reload
        expect(expense.ml_correction_count).to eq(1)
        expect(expense.ml_suggested_category_id).to be_nil

        # Simulate ML re-suggesting after the first correction cleared it
        expense.update_columns(
          ml_suggested_category_id: ml_category.id,
          category_id: other_category.id
        )
        described_class.new(
          expense_ids: [ expense.id ],
          category_id: target_category.id,
          options: { track_ml_corrections: true, force_synchronous: true }
        ).call

        expect(expense.reload.ml_correction_count).to eq(2)
      end
    end

    context "when track_ml_corrections is false (default)", unit: true do
      let!(:expense_with_suggestion) do
        create(:expense,
          email_account: email_account,
          category: other_category,
          ml_suggested_category_id: ml_category.id,
          ml_correction_count: 0)
      end
      let(:service) do
        described_class.new(
          expense_ids: [ expense_with_suggestion.id ],
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "does not modify ml_correction_count" do
        service.call

        expect(expense_with_suggestion.reload.ml_correction_count).to eq(0)
      end

      it "does not set ml_last_corrected_at" do
        service.call

        expect(expense_with_suggestion.reload.ml_last_corrected_at).to be_nil
      end

      it "does not clear ml_suggested_category_id" do
        service.call

        expect(expense_with_suggestion.reload.ml_suggested_category_id).to eq(ml_category.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ActionCable broadcast
  # ---------------------------------------------------------------------------

  describe "#call — ActionCable broadcast" do
    context "when broadcast_updates is true", unit: true do
      let(:service) do
        described_class.new(
          expense_ids: expense_ids,
          category_id: target_category.id,
          options: { broadcast_updates: true, force_synchronous: true }
        )
      end

      before { allow(ActionCable.server).to receive(:broadcast) }

      it "does not raise" do
        expect { service.call }.not_to raise_error
      end

      it "broadcasts to the correct channel for each expense" do
        service.call

        expenses.each do |expense|
          expect(ActionCable.server).to have_received(:broadcast).with(
            "expenses_#{expense.email_account_id}",
            hash_including(action: "categorized", expense_id: expense.id)
          )
        end
      end

      it "includes category_id in every broadcast payload" do
        payloads = []
        allow(ActionCable.server).to receive(:broadcast) do |_ch, payload|
          payloads << payload
        end
        service.call

        expect(payloads).to all(include(category_id: target_category.id))
      end

      it "includes category_name in every broadcast payload" do
        payloads = []
        allow(ActionCable.server).to receive(:broadcast) do |_ch, payload|
          payloads << payload
        end
        service.call

        expect(payloads).to all(include(category_name: target_category.name))
      end

      it "broadcasts exactly once per expense" do
        service.call

        expect(ActionCable.server).to have_received(:broadcast)
          .exactly(expense_ids.size).times
      end

      it "still returns a successful result after broadcasting" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end
    end

    context "when broadcast_updates is false", unit: true do
      let(:service) do
        described_class.new(
          expense_ids: expense_ids,
          category_id: target_category.id,
          options: { broadcast_updates: false, force_synchronous: true }
        )
      end

      it "does not call ActionCable.server.broadcast" do
        expect(ActionCable.server).not_to receive(:broadcast)
        service.call
      end
    end

    context "when broadcast_updates is not specified", unit: true do
      let(:service) do
        described_class.new(
          expense_ids: expense_ids,
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "does not broadcast by default" do
        expect(ActionCable.server).not_to receive(:broadcast)
        service.call
      end
    end

    context "when broadcasting raises an error", unit: true do
      let(:service) do
        described_class.new(
          expense_ids: expense_ids,
          category_id: target_category.id,
          options: { broadcast_updates: true, force_synchronous: true }
        )
      end

      before do
        allow(ActionCable.server).to receive(:broadcast)
          .and_raise(StandardError, "Cable disconnected")
      end

      it "logs a warning message" do
        expect(Rails.logger).to receive(:warn)
          .with(/Failed to broadcast categorization updates/)
        service.call
      end

      it "still returns success after the broadcast failure" do
        allow(Rails.logger).to receive(:warn)
        result = service.call

        expect(result[:success]).to be true
      end

      it "does not include broadcast errors in result failures or errors" do
        allow(Rails.logger).to receive(:warn)
        result = service.call

        expect(result[:failures]).to be_empty
        expect(result[:errors]).to be_empty
      end

      it "still categorizes all expenses despite broadcast failure" do
        allow(Rails.logger).to receive(:warn)
        service.call

        expenses.each do |expense|
          expect(expense.reload.category_id).to eq(target_category.id)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fallback to individual updates
  # ---------------------------------------------------------------------------

  describe "#call — fallback to individual updates" do
    let(:service) do
      described_class.new(
        expense_ids: expense_ids,
        category_id: target_category.id,
        options: { force_synchronous: true }
      )
    end

    context "when update_all raises a StandardError", unit: true do
      before do
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(StandardError, "Batch update failed")
      end

      it "falls back to individual updates and returns success" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end

      it "categorizes each expense via individual update" do
        service.call

        expenses.each do |expense|
          expect(expense.reload.category_id).to eq(target_category.id)
        end
      end

      it "reports zero failures when all individual updates succeed" do
        result = service.call

        expect(result[:failures]).to be_empty
      end
    end

    context "when a specific individual update fails during fallback", unit: true do
      let(:failing_expense) { expenses.first }

      before do
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(StandardError, "Batch update failed")
        failing_id = failing_expense.id
        allow_any_instance_of(Expense).to receive(:update) do |expense, attrs|
          expense.id == failing_id ? false : expense.update_columns(attrs)
        end
        allow_any_instance_of(Expense).to receive(:errors).and_call_original
        allow(failing_expense).to receive(:errors).and_return(
          double(full_messages: [ "Category invalid" ])
        )
      end

      it "records the failure including the expense id" do
        result = service.call

        failure_ids = result[:failures].map { |f| f[:id] }
        expect(failure_ids).to include(failing_expense.id)
      end

      it "returns a successful result with partial failure info", unit: true do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(2)
      end
    end

    context "when batch update fails and fallback is used", unit: true do
      let(:service) do
        described_class.new(
          expense_ids: expense_ids,
          category_id: target_category.id,
          options: { track_ml_corrections: true, force_synchronous: true }
        )
      end

      before do
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(StandardError, "Batch update failed")
      end

      it "does not track ML corrections" do
        expect_any_instance_of(described_class).not_to receive(:track_ml_corrections)
        service.call
      end
    end
  end

  # ---------------------------------------------------------------------------
  # success_message
  # ---------------------------------------------------------------------------

  describe "#success_message" do
    let(:service) { described_class.new(expense_ids: expense_ids, category_id: target_category.id) }

    it "includes the expense count", unit: true do
      message = service.send(:success_message, 5)

      expect(message).to include("5")
    end

    it "includes the category name", unit: true do
      message = service.send(:success_message, 5)

      expect(message).to include(target_category.name)
    end

    it "contains Spanish text", unit: true do
      message = service.send(:success_message, 3)

      expect(message).to include("categorizados como")
      expect(message).to include("exitosamente")
    end

    it "uses 'category' as fallback when category is not found", unit: true do
      service_no_cat = described_class.new(expense_ids: expense_ids, category_id: 999_999)
      allow(Category).to receive(:exists?).and_return(true)
      allow(Category).to receive(:find_by).with(id: 999_999).and_return(nil)

      message = service_no_cat.send(:success_message, 3)

      expect(message).to include("category")
    end

    it "message is included in the call result", unit: true do
      service_call = described_class.new(
        expense_ids: expense_ids,
        category_id: target_category.id,
        options: { force_synchronous: true }
      )
      result = service_call.call

      expect(result[:message]).to include(target_category.name)
      expect(result[:message]).to include("3")
    end
  end

  # ---------------------------------------------------------------------------
  # background_job_class
  # ---------------------------------------------------------------------------

  describe "#background_job_class" do
    it "returns BulkCategorizationJob", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)

      expect(service.send(:background_job_class)).to eq(BulkCategorizationJob)
    end
  end

  # ---------------------------------------------------------------------------
  # Missing expenses
  # ---------------------------------------------------------------------------

  describe "#call — missing expenses", unit: true do
    context "when at least one expense ID is not found" do
      let(:mixed_ids) { expense_ids + [ 999_999 ] }
      let(:service) do
        described_class.new(
          expense_ids: mixed_ids,
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "returns failure" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found or unauthorized")
      end

      it "does not modify any expenses" do
        original_categories = expenses.map { |e| e.reload.category_id }
        service.call

        expenses.each_with_index do |expense, i|
          expect(expense.reload.category_id).to eq(original_categories[i])
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Background threshold
  # ---------------------------------------------------------------------------

  describe "#call — background threshold" do
    context "when expense count meets BACKGROUND_THRESHOLD", unit: true do
      let(:threshold) { Services::BulkOperations::BaseService::BACKGROUND_THRESHOLD }
      let(:large_ids) { Array.new(threshold) { |i| i + 1 } }
      let(:service) { described_class.new(expense_ids: large_ids, category_id: target_category.id) }

      it "enqueues BulkCategorizationJob" do
        allow(BulkCategorizationJob).to receive(:perform_later)
          .and_return(double("Job", job_id: "abc-123"))

        result = service.call

        expect(BulkCategorizationJob).to have_received(:perform_later)
        expect(result[:background]).to be true
      end

      it "includes a background processing message" do
        allow(BulkCategorizationJob).to receive(:perform_later)
          .and_return(double("Job", job_id: "abc-123"))

        result = service.call

        expect(result[:message]).to eq("Processing #{threshold} expenses in background")
      end
    end

    context "when force_synchronous is true even above threshold", unit: true do
      let(:threshold) { Services::BulkOperations::BaseService::BACKGROUND_THRESHOLD }
      let(:large_expenses) { create_list(:expense, threshold, email_account: email_account, category: other_category) }
      let(:service) do
        described_class.new(
          expense_ids: large_expenses.map(&:id),
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "processes synchronously without enqueueing a job" do
        expect(BulkCategorizationJob).not_to receive(:perform_later)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:background]).to be_falsey
        expect(result[:affected_count]).to eq(threshold)
      end
    end

    context "when expense count is below BACKGROUND_THRESHOLD", unit: true do
      let(:service) { described_class.new(expense_ids: expense_ids, category_id: target_category.id) }

      it "processes synchronously" do
        expect(BulkCategorizationJob).not_to receive(:perform_later)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:background]).to be_falsey
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases", unit: true do
    context "with some IDs that do not exist" do
      let(:ids_with_missing) { expense_ids + [ 999_991, 999_992 ] }
      let(:service) { described_class.new(expense_ids: ids_with_missing, category_id: target_category.id) }

      it "returns failure when any requested ID is not found", unit: true do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("2 expenses not found")
      end
    end

    context "with string IDs that look numeric" do
      let(:string_ids) { expense_ids.map(&:to_s) }
      let(:service) do
        described_class.new(
          expense_ids: string_ids,
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "categorizes expenses when IDs are strings" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end
    end

    context "with negative IDs" do
      let(:service) { described_class.new(expense_ids: [ -1, -2 ], category_id: target_category.id) }

      it "returns not-found for negative IDs" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("2 expenses not found")
      end
    end

    context "with max 32-bit integer IDs" do
      let(:service) { described_class.new(expense_ids: [ 2**31 - 1 ], category_id: target_category.id) }

      it "handles large IDs gracefully without raising" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found")
      end
    end

    context "with a single expense ID" do
      let(:service) do
        described_class.new(
          expense_ids: [ expense_ids.first ],
          category_id: target_category.id,
          options: { force_synchronous: true }
        )
      end

      it "categorizes the single expense" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(1)
        expect(expenses.first.reload.category_id).to eq(target_category.id)
      end
    end
  end
end
