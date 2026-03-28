# frozen_string_literal: true

require "rails_helper"

# Concrete subclass for testing the abstract BaseService
class TestBulkService < Services::BulkOperations::BaseService
  def perform_operation(expenses)
    { success_count: expenses.count, failures: [] }
  end

  def success_message(count)
    "#{count} items processed"
  end

  def background_job_class
    # Return a double that quacks like a job class
    Class.new do
      def self.perform_later(**_args)
        instance = new
        allow_any_instance_of(self) { |i| } rescue nil
        instance
      end
    end
  end
end

RSpec.describe Services::BulkOperations::BaseService, type: :service do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let!(:expenses) { create_list(:expense, 3, email_account: email_account, category: category) }
  let(:expense_ids) { expenses.map(&:id) }

  describe "constants" do
    it "defines BATCH_SIZE", unit: true do
      expect(described_class::BATCH_SIZE).to eq(100)
    end

    it "defines BACKGROUND_THRESHOLD", unit: true do
      expect(described_class::BACKGROUND_THRESHOLD).to eq(100)
    end
  end

  describe "#initialize" do
    it "sets expense_ids", unit: true do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.expense_ids).to eq(expense_ids)
    end

    it "sets user", unit: true do
      user = double("User", id: 1)
      service = TestBulkService.new(expense_ids: expense_ids, user: user)

      expect(service.user).to eq(user)
    end

    it "sets options", unit: true do
      opts = { force_synchronous: true }
      service = TestBulkService.new(expense_ids: expense_ids, options: opts)

      expect(service.options).to eq(opts)
    end

    it "initializes results with default values", unit: true do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.results).to include(
        success: false,
        affected_count: 0,
        failures: [],
        errors: [],
        message: nil
      )
    end

    it "defaults user to nil", unit: true do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.user).to be_nil
    end

    it "defaults options to empty hash", unit: true do
      service = TestBulkService.new(expense_ids: expense_ids)

      expect(service.options).to eq({})
    end
  end

  describe "#call - validations" do
    context "when expense_ids is nil", unit: true do
      let(:service) { TestBulkService.new(expense_ids: nil) }

      it "returns failure with validation errors" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end

    context "when expense_ids is not an array", unit: true do
      let(:service) { TestBulkService.new(expense_ids: "invalid") }

      it "returns failure with array validation error" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Expense ids must be an array")
      end
    end

    context "when expense_ids is an empty array", unit: true do
      let(:service) { TestBulkService.new(expense_ids: []) }

      it "returns failure indicating no expenses found" do
        result = service.call

        expect(result[:success]).to be false
      end
    end
  end

  describe "#call - synchronous processing" do
    context "with valid expense_ids within threshold", unit: true do
      let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

      it "returns success when all expenses are found" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
        expect(result[:message]).to eq("3 items processed")
      end
    end

    context "when some expense_ids are not found", unit: true do
      let(:missing_ids) { expense_ids + [ 999_999 ] }
      let(:service) { TestBulkService.new(expense_ids: missing_ids) }

      it "returns failure when not all expenses are found" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found or unauthorized")
      end
    end

    context "when perform_operation raises an error" do
      let(:service) { TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true }) }

      it "handles the error gracefully and returns failure", unit: true do
        allow(service).to receive(:perform_operation).and_raise(StandardError, "operation failed")

        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("operation failed")
      end
    end
  end

  describe "#call - background processing" do
    context "when expense count meets threshold", unit: true do
      let(:large_expense_ids) { Array.new(described_class::BACKGROUND_THRESHOLD) { |i| i + 1 } }

      it "enqueues a background job instead of processing synchronously" do
        service = TestBulkService.new(expense_ids: large_expense_ids)

        mock_job_class = Class.new do
          def self.perform_later(**_args)
            obj = new
            def obj.job_id = "test-job-id"
            obj
          end
        end

        allow(service).to receive(:background_job_class).and_return(mock_job_class)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:background]).to be true
        expect(result[:message]).to include("in background")
      end
    end

    context "when force_synchronous option is set", unit: true do
      let(:large_expense_ids) { expense_ids }

      it "processes synchronously even if count would trigger background" do
        service = TestBulkService.new(expense_ids: expense_ids, options: { force_synchronous: true })

        result = service.call

        expect(result).not_to have_key(:background)
      end
    end
  end

  describe "#call - user authorization" do
    context "without user (admin mode)", unit: true do
      let(:service) { TestBulkService.new(expense_ids: expense_ids, user: nil, options: { force_synchronous: true }) }

      it "processes all specified expenses" do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:affected_count]).to eq(3)
      end
    end

    context "with a user that has no email_accounts", unit: true do
      # Use an instance_double of AdminUser which doesn't have email_accounts
      let(:user) { instance_double(AdminUser, id: 1) }
      let(:service) { TestBulkService.new(expense_ids: expense_ids, user: user, options: { force_synchronous: true }) }

      it "allows access without per-user scoping when user lacks email_accounts" do
        result = service.call

        expect(result[:success]).to be true
      end
    end

    context "with a user whose email_accounts scopes the expenses", unit: true do
      let(:other_account) { create(:email_account) }
      let(:user) { double("User", id: 999, email_accounts: EmailAccount.where(id: other_account.id)) }
      let(:service) { TestBulkService.new(expense_ids: expense_ids, user: user, options: { force_synchronous: true }) }

      it "returns failure when user does not own the expenses" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:message]).to include("not found or unauthorized")
      end
    end
  end

  describe "#perform_operation" do
    it "raises NotImplementedError in the base class", unit: true do
      service = described_class.new(expense_ids: expense_ids)
      expect { service.send(:perform_operation, []) }.to raise_error(NotImplementedError)
    end
  end

  describe "#background_job_class" do
    it "raises NotImplementedError in the base class", unit: true do
      service = described_class.new(expense_ids: expense_ids)
      expect { service.send(:background_job_class) }.to raise_error(NotImplementedError)
    end
  end

  describe "#success_message" do
    it "returns a generic message by default in the base class", unit: true do
      service = described_class.new(expense_ids: expense_ids)
      expect(service.send(:success_message, 5)).to include("5")
    end
  end
end
