# frozen_string_literal: true

require "rails_helper"

# Concrete subclass for testing the abstract BaseService.
# Implements all abstract methods so we can exercise the base class logic directly.
class TestBulkService < Services::BulkOperations::BaseService
  attr_reader :last_operated_expenses

  def perform_operation(expenses)
    @last_operated_expenses = expenses
    { success_count: expenses.count, failures: [] }
  end

  def success_message(count)
    "#{count} items processed"
  end

  def background_job_class
    FakeBackgroundJob
  end
end

# Minimal job stub used as the background_job_class for TestBulkService.
# Defined at the class level so instance_double works in specs.
class FakeBackgroundJob
  def self.perform_later(**_args)
    new
  end

  def job_id
    "fake-job-id"
  end
end

RSpec.describe Services::BulkOperations::BaseService, type: :service, unit: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let!(:expenses) { create_list(:expense, 3, email_account: email_account, category: category) }
  let(:expense_ids) { expenses.map(&:id) }

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  describe "constants", unit: true do
    it "defines BATCH_SIZE as 100" do
      expect(described_class::BATCH_SIZE).to eq(100)
    end

    it "defines BACKGROUND_THRESHOLD as 100" do
      expect(described_class::BACKGROUND_THRESHOLD).to eq(100)
    end
  end

  # ---------------------------------------------------------------------------
  # #initialize
  # ---------------------------------------------------------------------------

  describe "#initialize", unit: true do
    it "sets expense_ids" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.expense_ids).to eq(expense_ids)
    end

    it "sets user when provided" do
      user = double("User", id: 1)
      service = TestBulkService.new(expense_ids: expense_ids, user: user)

      expect(service.user).to eq(user)
    end

    it "defaults user to nil when not provided" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.user).to be_nil
    end

    it "sets options when provided" do
      opts = { force_synchronous: true, broadcast_updates: false }
      service = TestBulkService.new(expense_ids: expense_ids, options: opts)

      expect(service.options).to eq(opts)
    end

    it "defaults options to empty hash when not provided" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.options).to eq({})
    end

    it "initializes results hash with default values" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.results).to include(
        success: false,
        affected_count: 0,
        failures: [],
        errors: [],
        message: nil
      )
    end

    it "initializes with nil expense_ids without raising" do
      expect { TestBulkService.new(expense_ids: nil) }.not_to raise_error
    end

    it "initializes with non-array expense_ids without raising" do
      expect { TestBulkService.new(expense_ids: "not-an-array") }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # Validation: expense_ids_must_be_array
  # ---------------------------------------------------------------------------

  describe "expense_ids_must_be_array validation", unit: true do
    it "is invalid when expense_ids is a string" do
      service = TestBulkService.new(expense_ids: "invalid")

      expect(service).not_to be_valid
      expect(service.errors[:expense_ids]).to include("must be an array")
    end

    it "is invalid when expense_ids is an integer" do
      service = TestBulkService.new(expense_ids: 123)

      expect(service).not_to be_valid
      expect(service.errors[:expense_ids]).to include("must be an array")
    end

    it "is invalid when expense_ids is a hash" do
      service = TestBulkService.new(expense_ids: { id: 1 })

      expect(service).not_to be_valid
      expect(service.errors[:expense_ids]).to include("must be an array")
    end

    it "is valid when expense_ids is an array" do
      service = TestBulkService.new(expense_ids: expense_ids)

      service.valid?
      expect(service.errors[:expense_ids]).not_to include("must be an array")
    end

    it "is invalid when expense_ids is nil (fails presence and array check)" do
      service = TestBulkService.new(expense_ids: nil)

      expect(service).not_to be_valid
      # nil fails presence validation; array check only adds when non-nil non-array
    end

    it "returns failure with array error message when called with non-array" do
      result = TestBulkService.new(expense_ids: "string").call

      expect(result[:success]).to be false
      expect(result[:errors]).to include("Expense ids must be an array")
    end

    it "returns failure with presence error message when called with nil" do
      result = TestBulkService.new(expense_ids: nil).call

      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: should_process_in_background?
  # ---------------------------------------------------------------------------

  describe "should_process_in_background? threshold logic", unit: true do
    let(:threshold) { described_class::BACKGROUND_THRESHOLD }

    it "processes in background when expense count equals threshold" do
      ids = Array.new(threshold) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids)

      expect(service.send(:should_process_in_background?)).to be true
    end

    it "processes in background when expense count exceeds threshold" do
      ids = Array.new(threshold + 10) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids)

      expect(service.send(:should_process_in_background?)).to be true
    end

    it "processes synchronously when expense count is below threshold" do
      ids = Array.new(threshold - 1) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids)

      expect(service.send(:should_process_in_background?)).to be false
    end

    it "processes synchronously when force_synchronous is true even at threshold" do
      ids = Array.new(threshold) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids, options: { force_synchronous: true })

      expect(service.send(:should_process_in_background?)).to be false
    end

    it "processes synchronously when force_synchronous is true above threshold" do
      ids = Array.new(threshold + 50) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids, options: { force_synchronous: true })

      expect(service.send(:should_process_in_background?)).to be false
    end

    it "processes in background when force_synchronous is false at threshold" do
      ids = Array.new(threshold) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: ids, options: { force_synchronous: false })

      expect(service.send(:should_process_in_background?)).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: process_synchronously
  # ---------------------------------------------------------------------------

  describe "process_synchronously", unit: true do
    context "happy path — all expenses found" do
      let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

      it "returns success result" do
        result = service.call

        expect(result[:success]).to be true
      end

      it "returns correct affected_count" do
        result = service.call

        expect(result[:affected_count]).to eq(expense_ids.size)
      end

      it "returns the success message from the subclass" do
        result = service.call

        expect(result[:message]).to eq("3 items processed")
      end

      it "passes the found expenses to perform_operation" do
        service.call

        expect(service.last_operated_expenses.map(&:id)).to match_array(expense_ids)
      end

      it "wraps operation in a database transaction" do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original

        service.call
      end
    end

    context "missing expenses path — not all IDs found" do
      let(:missing_ids) { expense_ids + [ 999_999 ] }
      let(:service) { TestBulkService.new(expense_ids: missing_ids, options: { force_synchronous: true }) }

      it "returns failure" do
        result = service.call

        expect(result[:success]).to be false
      end

      it "includes a message describing how many were not found" do
        result = service.call

        expect(result[:message]).to eq("1 expenses not found or unauthorized")
      end

      it "includes a permission error in errors" do
        result = service.call

        expect(result[:errors]).to include(
          "Some expenses were not found or you don't have permission to modify them"
        )
      end

      it "does not call perform_operation when expenses are missing" do
        expect(service).not_to receive(:perform_operation)

        service.call
      end
    end

    context "when perform_operation raises a StandardError" do
      let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

      before do
        allow(service).to receive(:perform_operation).and_raise(StandardError, "db write failed")
      end

      it "returns failure" do
        result = service.call

        expect(result[:success]).to be false
      end

      it "includes the error message in errors" do
        result = service.call

        expect(result[:errors]).to include("db write failed")
      end

      it "sets the generic error message" do
        result = service.call

        expect(result[:message]).to eq("Error processing operation")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: enqueue_background_job
  # ---------------------------------------------------------------------------

  describe "enqueue_background_job delegation", unit: true do
    let(:threshold) { described_class::BACKGROUND_THRESHOLD }
    let(:large_ids) { Array.new(threshold) { |i| i + 1 } }

    it "delegates to background_job_class.perform_later" do
      service = TestBulkService.new(expense_ids: large_ids)
      job_double = instance_double(FakeBackgroundJob, job_id: "job-abc")

      expect(FakeBackgroundJob).to receive(:perform_later).with(
        expense_ids: large_ids,
        user_id: nil,
        options: {}
      ).and_return(job_double)

      service.call
    end

    it "passes user_id from the user object" do
      user = double("User", id: 42)
      service = TestBulkService.new(expense_ids: large_ids, user: user)
      job_double = instance_double(FakeBackgroundJob, job_id: "job-abc")

      expect(FakeBackgroundJob).to receive(:perform_later).with(
        expense_ids: large_ids,
        user_id: 42,
        options: {}
      ).and_return(job_double)

      service.call
    end

    it "passes options to the background job" do
      opts = { notify: true }
      service = TestBulkService.new(expense_ids: large_ids, options: opts)
      job_double = instance_double(FakeBackgroundJob, job_id: "job-abc")

      expect(FakeBackgroundJob).to receive(:perform_later).with(
        expense_ids: large_ids,
        user_id: nil,
        options: opts
      ).and_return(job_double)

      service.call
    end

    it "returns success: true in the result" do
      service = TestBulkService.new(expense_ids: large_ids)
      allow(FakeBackgroundJob).to receive(:perform_later).and_return(
        instance_double(FakeBackgroundJob, job_id: "job-123")
      )

      result = service.call

      expect(result[:success]).to be true
    end

    it "returns background: true in the result" do
      service = TestBulkService.new(expense_ids: large_ids)
      allow(FakeBackgroundJob).to receive(:perform_later).and_return(
        instance_double(FakeBackgroundJob, job_id: "job-123")
      )

      result = service.call

      expect(result[:background]).to be true
    end

    it "returns the job_id from the enqueued job" do
      service = TestBulkService.new(expense_ids: large_ids)
      allow(FakeBackgroundJob).to receive(:perform_later).and_return(
        instance_double(FakeBackgroundJob, job_id: "job-xyz")
      )

      result = service.call

      expect(result[:job_id]).to eq("job-xyz")
    end

    it "returns a message mentioning the expense count" do
      service = TestBulkService.new(expense_ids: large_ids)
      allow(FakeBackgroundJob).to receive(:perform_later).and_return(
        instance_double(FakeBackgroundJob, job_id: "job-123")
      )

      result = service.call

      expect(result[:message]).to eq("Processing #{threshold} expenses in background")
    end

    context "when perform_later raises a StandardError" do
      it "returns failure with the error message" do
        service = TestBulkService.new(expense_ids: large_ids)
        allow(FakeBackgroundJob).to receive(:perform_later).and_raise(StandardError, "queue full")

        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("queue full")
      end

      it "logs the error" do
        service = TestBulkService.new(expense_ids: large_ids)
        allow(FakeBackgroundJob).to receive(:perform_later).and_raise(StandardError, "queue full")

        expect(Rails.logger).to receive(:error).with(/queue full/)

        service.call
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: find_authorized_expenses
  # ---------------------------------------------------------------------------

  describe "find_authorized_expenses", unit: true do
    context "without a user" do
      it "returns all matching expenses regardless of email_account" do
        other_account = create(:email_account)
        other_expenses = create_list(:expense, 2, email_account: other_account, category: category)
        all_ids = expense_ids + other_expenses.map(&:id)

        service = TestBulkService.new(expense_ids: all_ids, user: nil, options: { force_synchronous: true })
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(5)
      end
    end

    context "with a user that does not respond to email_accounts" do
      let(:user) { instance_double(AdminUser, id: 1) }

      it "does not scope expenses to email_accounts" do
        service = TestBulkService.new(expense_ids: expense_ids, user: user, options: { force_synchronous: true })
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end
    end

    context "with a user that responds to email_accounts" do
      it "scopes expenses to the user's email accounts" do
        other_account = create(:email_account)
        other_expenses = create_list(:expense, 2, email_account: other_account, category: category)
        user = double("User", id: 99, email_accounts: EmailAccount.where(id: other_account.id))

        # Request expenses from email_account, but user only owns other_account
        service = TestBulkService.new(expense_ids: expense_ids, user: user, options: { force_synchronous: true })
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found or unauthorized")
      end

      it "returns expenses when user owns the correct email account" do
        user = double("User", id: 99, email_accounts: EmailAccount.where(id: email_account.id))

        service = TestBulkService.new(expense_ids: expense_ids, user: user, options: { force_synchronous: true })
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: handle_error
  # ---------------------------------------------------------------------------

  describe "handle_error", unit: true do
    let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

    it "logs the error message with Rails.logger.error" do
      allow(service).to receive(:perform_operation).and_raise(StandardError, "something exploded")

      expect(Rails.logger).to receive(:error).with("Bulk operation error: something exploded")

      service.call
    end

    it "sets success to false in results" do
      allow(service).to receive(:perform_operation).and_raise(StandardError, "boom")

      result = service.call

      expect(result[:success]).to be false
    end

    it "sets message to generic error text" do
      allow(service).to receive(:perform_operation).and_raise(StandardError, "boom")

      result = service.call

      expect(result[:message]).to eq("Error processing operation")
    end

    it "includes the original error message in errors array" do
      allow(service).to receive(:perform_operation).and_raise(StandardError, "original error")

      result = service.call

      expect(result[:errors]).to include("original error")
    end

    it "preserves existing results keys while merging error state" do
      allow(service).to receive(:perform_operation).and_raise(StandardError, "err")

      result = service.call

      expect(result).to have_key(:affected_count)
      expect(result).to have_key(:failures)
    end
  end

  # ---------------------------------------------------------------------------
  # Private method: process_operation_result
  # ---------------------------------------------------------------------------

  describe "process_operation_result", unit: true do
    let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

    context "when perform_operation returns a Hash" do
      it "sets affected_count from success_count key" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 2, failures: [] }
        )

        result = service.call

        expect(result[:affected_count]).to eq(2)
      end

      it "sets failures from failures key" do
        failure = { id: 1, error: "failed" }
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 2, failures: [ failure ] }
        )

        result = service.call

        expect(result[:failures]).to include(failure)
      end

      it "sets message from success_message with success_count" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [] }
        )

        result = service.call

        expect(result[:message]).to eq("3 items processed")
      end

      it "defaults affected_count to 0 when success_count key is absent" do
        allow(service).to receive(:perform_operation).and_return(
          { failures: [] }
        )

        result = service.call

        expect(result[:affected_count]).to eq(0)
      end

      it "includes undo_id when present in the result hash" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [], undo_id: "undo-abc-123" }
        )

        result = service.call

        expect(result[:undo_id]).to eq("undo-abc-123")
      end

      it "includes undo_time_remaining when present in the result hash" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [], undo_time_remaining: 30 }
        )

        result = service.call

        expect(result[:undo_time_remaining]).to eq(30)
      end

      it "does not include undo_id key when absent from the result hash" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [] }
        )

        result = service.call

        expect(result).not_to have_key(:undo_id)
      end

      it "does not include undo_time_remaining key when absent from the result hash" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [] }
        )

        result = service.call

        expect(result).not_to have_key(:undo_time_remaining)
      end

      it "sets success to true" do
        allow(service).to receive(:perform_operation).and_return(
          { success_count: 3, failures: [] }
        )

        result = service.call

        expect(result[:success]).to be true
      end
    end

    context "when perform_operation returns a non-Hash result" do
      it "sets affected_count to the total number of expense_ids" do
        allow(service).to receive(:perform_operation).and_return(true)

        result = service.call

        expect(result[:affected_count]).to eq(expense_ids.size)
      end

      it "sets message using success_message with expense_ids count" do
        allow(service).to receive(:perform_operation).and_return(true)

        result = service.call

        expect(result[:message]).to eq("3 items processed")
      end

      it "sets success to true" do
        allow(service).to receive(:perform_operation).and_return(nil)

        result = service.call

        expect(result[:success]).to be true
      end

      it "works when perform_operation returns an integer" do
        allow(service).to receive(:perform_operation).and_return(3)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(expense_ids.size)
      end

      it "works when perform_operation returns a symbol" do
        allow(service).to receive(:perform_operation).and_return(:ok)

        result = service.call

        expect(result[:success]).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Abstract methods: NotImplementedError contract
  # ---------------------------------------------------------------------------

  describe "#perform_operation (abstract)", unit: true do
    it "raises NotImplementedError when called on the base class directly" do
      service = described_class.new(expense_ids: expense_ids)

      expect { service.send(:perform_operation, []) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement perform_operation"
      )
    end
  end

  describe "#background_job_class (abstract)", unit: true do
    it "raises NotImplementedError when called on the base class directly" do
      service = described_class.new(expense_ids: expense_ids)

      expect { service.send(:background_job_class) }.to raise_error(
        NotImplementedError,
        "Subclasses must implement background_job_class"
      )
    end
  end

  describe "#success_message (base implementation)", unit: true do
    it "returns a string containing the count" do
      service = described_class.new(expense_ids: expense_ids)

      message = service.send(:success_message, 7)

      expect(message).to include("7")
    end

    it "returns a string" do
      service = described_class.new(expense_ids: expense_ids)

      expect(service.send(:success_message, 0)).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # ActiveModel::Model inclusion
  # ---------------------------------------------------------------------------

  describe "ActiveModel::Model integration", unit: true do
    it "responds to valid?" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service).to respond_to(:valid?)
    end

    it "responds to errors" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service).to respond_to(:errors)
    end

    it "is valid with a proper array of expense_ids" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service).to be_valid
    end

    it "is invalid without expense_ids" do
      service = TestBulkService.new(expense_ids: nil)

      expect(service).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # #call — top-level routing and edge cases
  # ---------------------------------------------------------------------------

  describe "#call routing", unit: true do
    it "routes to process_synchronously when below threshold" do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service).to receive(:process_synchronously).and_call_original

      service.call
    end

    it "routes to enqueue_background_job when at or above threshold" do
      large_ids = Array.new(described_class::BACKGROUND_THRESHOLD) { |i| i + 1 }
      service = TestBulkService.new(expense_ids: large_ids)
      allow(FakeBackgroundJob).to receive(:perform_later).and_return(
        instance_double(FakeBackgroundJob, job_id: "j1")
      )

      expect(service).to receive(:enqueue_background_job).and_call_original

      service.call
    end

    it "short-circuits on validation failure before touching expenses" do
      expect(Expense).not_to receive(:where)

      TestBulkService.new(expense_ids: nil).call
    end

    it "returns failure for empty array (presence validation fails)" do
      result = TestBulkService.new(expense_ids: []).call

      expect(result[:success]).to be false
      expect(result[:errors]).not_to be_empty
    end
  end
end
