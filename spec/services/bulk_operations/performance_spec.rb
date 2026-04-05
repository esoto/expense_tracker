# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Bulk Operations Performance", type: :performance do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

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

        # Should be fast with delete_all (relaxed for CI/test variability)
        expect(execution_time).to be < 1.0
        expect(Expense.count).to eq(initial_count - 200)
      end
    end
  end
end
