require 'rails_helper'

RSpec.describe Expense, type: :model, integration: true do
  let(:email_account) { create(:email_account, email: "test_#{SecureRandom.hex(4)}@example.com", provider: 'gmail', bank_name: 'BAC', encrypted_password: 'pass') }
  let(:category) { create(:category, name: 'Test Category') }

  describe 'validations', integration: true do
    it 'is valid with valid attributes' do
      expense = build(:expense,
        amount: 100.50,
        transaction_date: Time.current,
        description: 'Test expense',
        email_account: email_account
      )
      expect(expense).to be_valid
    end

    it 'requires amount' do
      expense = build(:expense, amount: nil, transaction_date: Time.current, email_account: email_account)
      expect(expense).not_to be_valid
      expect(expense.errors[:amount]).to include("can't be blank")
    end


    it 'requires transaction_date' do
      expense = build(:expense, amount: 100, transaction_date: nil, email_account: email_account)
      expect(expense).not_to be_valid
      expect(expense.errors[:transaction_date]).to include("can't be blank")
    end

    it 'allows nil email_account for manual entry' do
      expense = build(:expense, amount: 100, email_account: nil, transaction_date: Time.current)
      expect(expense).to be_valid
    end

    it 'is valid with a real email_account' do
      expense = build(:expense, amount: 100, email_account: email_account, transaction_date: Time.current)
      expect(expense).to be_valid
    end

    it 'validates category exists when provided' do
      # Valid category_id should pass
      valid_expense = build(:expense, category_id: category.id, email_account: email_account)
      expect(valid_expense).to be_valid

      # Nil category_id should pass (optional association)
      nil_category_expense = build(:expense, category_id: nil, email_account: email_account)
      expect(nil_category_expense).to be_valid

      # Non-existent category_id should fail
      invalid_expense = build(:expense, category_id: 99999, email_account: email_account)
      expect(invalid_expense).not_to be_valid
      expect(invalid_expense.errors[:category]).to include("must exist")
    end

    it 'validates currency inclusion' do
      valid_currencies = [ 'crc', 'usd', 'eur' ]
      valid_currencies.each do |currency|
        expense = build(:expense, currency: currency)
        expect(expense).to be_valid, "#{currency} should be valid"
      end

      expect {
        build(:expense, currency: 'invalid')
      }.to raise_error(ArgumentError, "'invalid' is not a valid currency")
    end
  end

  describe 'associations', integration: true do
    let(:expense) { create(:expense, email_account: email_account, category: category) }

    it 'belongs to email_account optionally' do
      expect(expense.email_account).to eq(email_account)

      manual_expense = create(:expense, :manual_entry)
      expect(manual_expense.email_account).to be_nil
    end

    it 'belongs to category optionally' do
      expect(expense.category).to eq(category)

      expense_without_category = create(:expense, category: nil, email_account: email_account)
      expect(expense_without_category.category).to be_nil
    end
  end

  describe 'scopes', integration: true do
    let!(:recent_expense) { create(:expense, amount: 100, transaction_date: 1.day.ago, email_account: email_account) }
    let!(:old_expense) { create(:expense, amount: 50, transaction_date: 1.week.ago, email_account: email_account) }
    let!(:pending_expense) { create(:expense, amount: 75, transaction_date: Time.current, email_account: email_account, status: 'pending') }
    let!(:processed_expense) { create(:expense, amount: 125, transaction_date: Time.current, email_account: email_account, status: 'processed') }

    it 'orders recent expenses by transaction_date desc' do
      recent_expenses = Expense.recent
      expect(recent_expenses.map(&:id)).to include(pending_expense.id, processed_expense.id, recent_expense.id, old_expense.id)
      expect(recent_expenses.last).to eq(old_expense) # oldest last
    end

    it 'filters by date range' do
      start_date = 2.days.ago
      end_date = Time.current

      expenses_in_range = Expense.by_date_range(start_date, end_date)
      expect(expenses_in_range).to include(recent_expense, pending_expense, processed_expense)
      expect(expenses_in_range).not_to include(old_expense)
    end

    it 'filters by status' do
      pending_expenses = Expense.by_status('pending')
      expect(pending_expenses).to include(pending_expense)
      expect(pending_expenses).not_to include(processed_expense)
    end

    it 'filters by currency' do
      usd_expense = create(:expense, amount: 20, transaction_date: Time.current, email_account: email_account, currency: 'usd')
      crc_expenses = Expense.crc
      usd_expenses = Expense.usd

      expect(crc_expenses).to include(recent_expense) # defaults to crc
      expect(crc_expenses).not_to include(usd_expense)
      expect(usd_expenses).to include(usd_expense)
    end
  end

  describe 'scopes (additional)', integration: true do
    let!(:categorized_expense) { create(:expense, amount: 100, email_account: email_account, category: category) }
    let!(:uncategorized_expense) { create(:expense, :without_category, amount: 200, email_account: email_account) }
    let!(:this_month_expense) { create(:expense, amount: 150, email_account: email_account, transaction_date: Date.current.beginning_of_month + 5.days) }
    let!(:last_month_expense) { create(:expense, amount: 75, email_account: email_account, transaction_date: 1.month.ago) }
    let!(:this_year_expense) { create(:expense, amount: 300, email_account: email_account, transaction_date: Date.current.beginning_of_year + 2.months) }
    let!(:last_year_expense) { create(:expense, amount: 50, email_account: email_account, transaction_date: 1.year.ago) }
    let!(:amount_range_expense_1) { create(:expense, amount: 25, email_account: email_account) }
    let!(:amount_range_expense_2) { create(:expense, amount: 250, email_account: email_account) }

    it 'filters uncategorized expenses' do
      uncategorized = Expense.uncategorized
      expect(uncategorized).to include(uncategorized_expense)
      expect(uncategorized).not_to include(categorized_expense)
    end

    it 'filters expenses for this month' do
      this_month = Expense.this_month
      expect(this_month).to include(this_month_expense)
      expect(this_month).not_to include(last_month_expense)
    end

    it 'filters expenses for this year' do
      this_year = Expense.this_year
      expect(this_year).to include(this_year_expense)
      expect(this_year).not_to include(last_year_expense)
    end

    it 'filters by amount range' do
      in_range = Expense.by_amount_range(20, 100)
      expect(in_range).to include(amount_range_expense_1)
      expect(in_range).not_to include(amount_range_expense_2)
    end
  end

  describe 'class methods', integration: true do
    let!(:expense1) { create(:expense, :with_category, amount: 100, transaction_date: Time.current, email_account: email_account, category: category) }
    let!(:expense2) { create(:expense, :with_category, amount: 200, transaction_date: Time.current, email_account: email_account, category: category) }
    let!(:expense3) { create(:expense, :with_category, amount: 150, transaction_date: 1.month.ago, email_account: email_account, category: category) }

    it 'calculates total amount for period' do
      start_date = 1.hour.ago
      end_date = 1.hour.from_now

      total = Expense.total_amount_for_period(start_date, end_date)
      expect(total).to eq(300)
    end

    it 'provides category summary' do
      summary = Expense.by_category_summary
      expect(summary[category.name]).to eq(450) # 100 + 200 + 150
    end

    it 'provides monthly summary' do
      summary = Expense.monthly_summary
      expect(summary).to be_a(Hash)
      expect(summary.values.sum).to eq(450)
    end
  end

  describe 'instance methods', integration: true do
    let(:crc_expense) { create(:expense, :with_category, amount: 95000, transaction_date: Time.current, email_account: email_account, currency: 'crc') }
    let(:usd_expense) { create(:expense, :with_category, amount: 20.50, transaction_date: Time.current, email_account: email_account, currency: 'usd') }



    describe 'status helper methods', integration: true do
      it 'has helper methods for all statuses' do
        pending_expense = create(:expense, amount: 100, transaction_date: Time.current, email_account: email_account, status: 'pending')
        processed_expense = create(:expense, amount: 100, transaction_date: Time.current, email_account: email_account, status: 'processed')
        failed_expense = create(:expense, amount: 100, transaction_date: Time.current, email_account: email_account, status: 'failed')
        duplicate_expense = create(:expense, amount: 100, transaction_date: Time.current, email_account: email_account, status: 'duplicate')

        expect(pending_expense).to be_pending
        expect(processed_expense).to be_processed
        expect(failed_expense).to be_failed
        expect(duplicate_expense).to be_duplicate
      end
    end

    describe '#bank_name', integration: true do
      it 'returns column value when set' do
        expense = create(:expense, email_account: email_account)
        expect(expense.bank_name).to eq('BAC')
      end

      it 'returns "Manual" for manual entries' do
        expense = create(:expense, :manual_entry)
        expect(expense.bank_name).to eq('Manual')
      end

      it 'populates from email account on save when blank' do
        expense = create(:expense, bank_name: nil, email_account: email_account)
        expect(expense.reload.bank_name).to eq('BAC')
      end
    end

    describe '#display_description', integration: true do
      it 'returns description when present' do
        expense = create(:expense, description: 'Test description', merchant_name: 'Test Merchant', email_account: email_account)
        expect(expense.display_description).to eq('Test description')
      end

      it 'returns merchant_name when description is blank' do
        expense = create(:expense, description: '', merchant_name: 'Test Merchant', email_account: email_account)
        expect(expense.display_description).to eq('Test Merchant')
      end

      it 'returns default text when both description and merchant_name are blank' do
        expense = create(:expense, description: '', merchant_name: '', email_account: email_account)
        expect(expense.display_description).to eq('Unknown Transaction')
      end
    end

    describe '#parsed_email_data', integration: true do
      it 'returns parsed JSON data' do
        data = { 'amount' => '100.50', 'merchant' => 'Test Merchant' }
        expense = create(:expense, parsed_data: data.to_json, email_account: email_account)
        expect(expense.parsed_email_data).to eq(data)
      end

      it 'returns empty hash for invalid JSON' do
        expense = create(:expense, parsed_data: 'invalid json', email_account: email_account)
        expect(expense.parsed_email_data).to eq({})
      end

      it 'returns empty hash when parsed_data is nil' do
        expense = create(:expense, parsed_data: nil, email_account: email_account)
        expect(expense.parsed_email_data).to eq({})
      end
    end

    describe '#parsed_email_data=', integration: true do
      it 'sets parsed_data as JSON string' do
        expense = create(:expense, email_account: email_account)
        data = { 'amount' => '100.50', 'merchant' => 'Test Merchant' }
        expense.parsed_email_data = data
        expect(expense.parsed_data).to eq(data.to_json)
      end
    end

    describe '#category_name', integration: true do
      let(:expense) { create(:expense, category: category, email_account: email_account) }

      it 'returns category name when category is present' do
        expect(expense.category_name).to eq(category.name)
      end

      context 'when category is nil' do
        let(:expense_without_category) { create(:expense, category: nil, email_account: email_account) }

        it 'returns "Uncategorized" when category is nil' do
          expect(expense_without_category.category_name).to eq('Uncategorized')
        end
      end
    end
  end

  describe 'manual expense creation', :unit do
    it 'creates a valid expense without email_account' do
      expense = build(:expense, :manual_entry,
        amount: 5000,
        transaction_date: Date.current,
        description: 'Manual grocery purchase',
        currency: 'crc',
        status: 'processed'
      )
      expect(expense).to be_valid
      expect(expense.save).to be true
      expect(expense.email_account_id).to be_nil
    end

    it 'persists and reloads correctly' do
      expense = create(:expense, :manual_entry,
        amount: 250.00,
        description: 'Cash payment'
      )
      reloaded = Expense.find(expense.id)
      expect(reloaded.email_account_id).to be_nil
      expect(reloaded.bank_name).to eq('Manual')
    end

    it 'does not break formatted_amount for manual expenses' do
      expense = build(:expense, :manual_entry, amount: 1500, currency: 'crc')
      expect(expense.formatted_amount).to eq('₡1500.0')
    end

    it 'handles display_description for manual expenses' do
      expense = build(:expense, :manual_entry, description: 'Manual entry test', merchant_name: nil)
      expect(expense.display_description).to eq('Manual entry test')
    end
  end

  describe 'callbacks', integration: true do
    describe 'after_commit :clear_dashboard_cache', integration: true do
      it 'clears dashboard cache after creating an expense' do
        expect(Services::DashboardService).to receive(:clear_cache)
        create(:expense, email_account: email_account)
      end

      it 'clears dashboard cache after updating an expense' do
        expense = create(:expense, email_account: email_account)
        expect(Services::DashboardService).to receive(:clear_cache)
        expense.update(amount: 200.0)
      end

      it 'clears dashboard cache after destroying an expense' do
        expense = create(:expense, email_account: email_account)
        expect(Services::DashboardService).to receive(:clear_cache)
        expense.destroy
      end
    end
  end
end
