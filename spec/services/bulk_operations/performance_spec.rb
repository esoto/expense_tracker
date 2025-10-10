# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Bulk Operations Performance", type: :performance do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

  describe "Services::BulkOperations::CategorizationService" do
    context "with 500 expenses" do
      let!(:expenses) do
        expenses = []
        500.times do |i|
          expenses << build(:expense,
            email_account: email_account,
            category: nil,
            merchant_name: "Merchant #{i}",
            amount: 100 + i
          )
        end
        Expense.import(expenses) # Use bulk insert for test setup
        Expense.where(email_account: email_account).pluck(:id)
      end

      it "completes within 500ms using batch updates" do
        service = Services::BulkOperations::CategorizationService.new(
          expense_ids: expenses,
          category_id: category.id,
          options: { force_synchronous: true }
        )

        execution_time = Benchmark.realtime do
          result = service.call
          expect(result[:success]).to be true
          expect(result[:affected_count]).to eq(500)
        end

        # Should complete in under 500ms (vs 2-4 seconds with individual updates)
        expect(execution_time).to be < 0.5

        # Verify all expenses were updated
        expect(Expense.where(id: expenses, category_id: category.id).count).to eq(500)
      end
    end

    context "with 100 expenses" do
      let!(:expenses) do
        create_list(:expense, 100, email_account: email_account, category: nil).map(&:id)
      end

      it "uses background job for large operations" do
        service = Services::BulkOperations::CategorizationService.new(
          expense_ids: expenses,
          category_id: category.id
        )

        result = service.call

        # Should return immediately with background job info
        expect(result[:success]).to be true
        expect(result[:background]).to be true
        expect(result[:job_id]).to be_present
      end
    end

    context "with 50 expenses" do
      let!(:expenses) do
        create_list(:expense, 50, email_account: email_account, category: nil).map(&:id)
      end

      it "processes synchronously for small operations" do
        service = Services::BulkOperations::CategorizationService.new(
          expense_ids: expenses,
          category_id: category.id
        )

        result = service.call

        # Should process immediately
        expect(result[:success]).to be true
        expect(result[:background]).to be_falsey
        expect(result[:affected_count]).to eq(50)

        # Verify all expenses were updated
        expect(Expense.where(id: expenses, category_id: category.id).count).to eq(50)
      end
    end
  end

  describe "Services::BulkOperations::StatusUpdateService" do
    context "with 500 expenses" do
      let!(:expenses) do
        expenses = []
        500.times do |i|
          expenses << build(:expense,
            email_account: email_account,
            status: "pending",
            merchant_name: "Merchant #{i}"
          )
        end
        Expense.import(expenses)
        Expense.where(email_account: email_account).pluck(:id)
      end

      it "completes status update within 500ms" do
        service = Services::BulkOperations::StatusUpdateService.new(
          expense_ids: expenses,
          status: "processed",
          options: { force_synchronous: true }
        )

        execution_time = Benchmark.realtime do
          result = service.call
          expect(result[:success]).to be true
        end

        expect(execution_time).to be < 0.5
        expect(Expense.where(id: expenses, status: "processed").count).to eq(500)
      end
    end
  end

  describe "Services::BulkOperations::DeletionService" do
    context "with 200 expenses" do
      let!(:expenses) do
        create_list(:expense, 200, email_account: email_account).map(&:id)
      end

      it "deletes all expenses efficiently" do
        initial_count = Expense.count

        service = Services::BulkOperations::DeletionService.new(
          expense_ids: expenses,
          options: { force_synchronous: true, skip_callbacks: true }
        )

        execution_time = Benchmark.realtime do
          result = service.call
          expect(result[:success]).to be true
          expect(result[:affected_count]).to eq(200)
        end

        # Should be very fast with delete_all
        expect(execution_time).to be < 0.2
        expect(Expense.count).to eq(initial_count - 200)
      end
    end
  end
end
