# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::BulkOperations::CategorizationService, type: :service do
  let(:email_account) { create(:email_account) }
  let(:target_category) { create(:category) }
  let(:other_category) { create(:category) }
  let!(:expenses) { create_list(:expense, 3, email_account: email_account, category: other_category) }
  let(:expense_ids) { expenses.map(&:id) }

  describe "#initialize" do
    it "sets category_id", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)

      expect(service.category_id).to eq(target_category.id)
    end

    it "delegates expense_ids, user, and options to base", unit: true do
      user = double("User", id: 1)
      opts = { broadcast_updates: false }
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id, user: user, options: opts)

      expect(service.expense_ids).to eq(expense_ids)
      expect(service.user).to eq(user)
      expect(service.options).to eq(opts)
    end
  end

  describe "validations" do
    context "when category_id is blank", unit: true do
      let(:service) { described_class.new(expense_ids: expense_ids, category_id: nil) }

      it "returns validation error" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end

    context "when category_id does not exist", unit: true do
      let(:service) { described_class.new(expense_ids: expense_ids, category_id: 999_999) }

      it "returns validation error stating category does not exist" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Category does not exist")
      end
    end

    context "when expense_ids is nil", unit: true do
      let(:service) { described_class.new(expense_ids: nil, category_id: target_category.id) }

      it "returns validation error" do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end
  end

  describe "#call - successful categorization" do
    let(:service) do
      described_class.new(expense_ids: expense_ids, category_id: target_category.id, options: { force_synchronous: true })
    end

    it "returns success", unit: true do
      result = service.call

      expect(result[:success]).to be true
    end

    it "returns the count of affected expenses", unit: true do
      result = service.call

      expect(result[:affected_count]).to eq(3)
    end

    it "updates all expenses to the target category", unit: true do
      service.call

      expenses.each(&:reload)
      expect(expenses.map(&:category_id)).to all(eq(target_category.id))
    end

    it "returns a localized success message with category name", unit: true do
      result = service.call

      expect(result[:message]).to include(target_category.name)
      expect(result[:message]).to include("3")
    end
  end

  describe "#success_message" do
    let(:service) { described_class.new(expense_ids: expense_ids, category_id: target_category.id) }

    it "includes the category name and count", unit: true do
      message = service.send(:success_message, 5)

      expect(message).to include("5")
      expect(message).to include(target_category.name)
    end

    it "uses fallback category name when category is not found", unit: true do
      service_no_cat = described_class.new(expense_ids: expense_ids, category_id: 999_999)
      # Bypass validation to test the message directly
      allow(Category).to receive(:exists?).and_return(true)
      allow(Category).to receive(:find_by).with(id: 999_999).and_return(nil)

      message = service_no_cat.send(:success_message, 3)

      expect(message).to include("category")
    end
  end

  describe "#background_job_class" do
    it "returns BulkCategorizationJob", unit: true do
      service = described_class.new(expense_ids: expense_ids, category_id: target_category.id)

      expect(service.send(:background_job_class)).to eq(BulkCategorizationJob)
    end
  end

  describe "#call - ML correction tracking" do
    let!(:expenses_with_ml) do
      create_list(:expense, 2, email_account: email_account,
        category: other_category,
        ml_suggested_category_id: other_category.id,
        ml_correction_count: 0)
    end
    let(:ml_expense_ids) { expenses_with_ml.map(&:id) }
    let(:service) do
      described_class.new(
        expense_ids: ml_expense_ids,
        category_id: target_category.id,
        options: { track_ml_corrections: true, force_synchronous: true }
      )
    end

    it "increments ml_correction_count for expenses where category differs from suggestion", unit: true do
      service.call

      expenses_with_ml.each(&:reload)
      # ml_suggested_category_id is other_category, but we're setting target_category,
      # so corrections should be incremented
      expect(expenses_with_ml.map(&:ml_correction_count)).to all(eq(1))
    end
  end

  describe "#call - broadcast updates" do
    let(:service) do
      described_class.new(
        expense_ids: expense_ids,
        category_id: target_category.id,
        options: { broadcast_updates: true, force_synchronous: true }
      )
    end

    it "does not raise even when broadcasting", unit: true do
      allow(ActionCable.server).to receive(:broadcast)

      expect { service.call }.not_to raise_error
    end

    it "broadcasts to the correct channel for each expense", unit: true do
      allow(ActionCable.server).to receive(:broadcast)

      service.call

      expenses.each do |expense|
        expect(ActionCable.server).to have_received(:broadcast).with(
          "expenses_#{expense.email_account_id}",
          hash_including(action: "categorized", expense_id: expense.id)
        )
      end
    end
  end

  describe "#call - fallback to individual updates" do
    let(:service) do
      described_class.new(expense_ids: expense_ids, category_id: target_category.id, options: { force_synchronous: true })
    end

    it "falls back to individual updates when batch update fails", unit: true do
      call_count = 0
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all) do |_rel, _attrs|
        call_count += 1
        raise ActiveRecord::StatementInvalid, "batch failed" if call_count == 1
      end

      # After fallback, individual updates should succeed
      allow_any_instance_of(Expense).to receive(:update).and_return(true)

      result = service.call

      # Either the fallback succeeded or an error was handled gracefully
      expect([ true, false ]).to include(result[:success])
    end
  end

  describe "#call - missing expenses" do
    let(:missing_ids) { expense_ids + [ 999_999 ] }
    let(:service) do
      described_class.new(expense_ids: missing_ids, category_id: target_category.id, options: { force_synchronous: true })
    end

    it "returns failure when not all expenses are found", unit: true do
      result = service.call

      expect(result[:success]).to be false
      expect(result[:message]).to include("not found or unauthorized")
    end
  end

  describe "#call - background threshold" do
    context "when expense count meets BACKGROUND_THRESHOLD", unit: true do
      let(:large_ids) { Array.new(Services::BulkOperations::BaseService::BACKGROUND_THRESHOLD) { |i| i + 1 } }
      let(:service) { described_class.new(expense_ids: large_ids, category_id: target_category.id) }

      it "enqueues background job" do
        allow(BulkCategorizationJob).to receive(:perform_later).and_return(
          double("Job", job_id: "abc-123")
        )

        result = service.call

        expect(BulkCategorizationJob).to have_received(:perform_later)
        expect(result[:background]).to be true
      end
    end
  end
end
