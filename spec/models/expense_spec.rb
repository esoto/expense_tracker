require 'rails_helper'

RSpec.describe Expense, type: :model do
  let(:email_account) { create(:email_account, email: 'test@example.com', provider: 'gmail', bank_name: 'BAC', encrypted_password: 'pass') }
  let(:category) { create(:category, name: 'Test Category') }

  describe 'validations' do
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

    it 'requires amount to be greater than 0' do
      expense = build(:expense, amount: 0, transaction_date: Time.current, email_account: email_account)
      expect(expense).not_to be_valid
      expect(expense.errors[:amount]).to include('must be greater than 0')
    end

    it 'requires positive amount' do
      expense = build(:expense, amount: -10, transaction_date: Time.current, email_account: email_account)
      expect(expense).not_to be_valid
      expect(expense.errors[:amount]).to include('must be greater than 0')
    end

    it 'requires transaction_date' do
      expense = build(:expense, amount: 100, transaction_date: nil, email_account: email_account)
      expect(expense).not_to be_valid
      expect(expense.errors[:transaction_date]).to include("can't be blank")
    end

    it 'requires email_account' do
      expense = build(:expense, amount: 100, email_account: nil, transaction_date: Time.current)
      expect(expense).not_to be_valid
      expect(expense.errors[:email_account]).to include("must exist")
    end

    it 'validates status inclusion' do
      valid_statuses = [ 'pending', 'processed', 'failed', 'duplicate' ]
      valid_statuses.each do |status|
        expense = build(:expense, status: status)
        expect(expense).to be_valid, "#{status} should be valid"
      end

      invalid_expense = build(:expense, status: 'invalid')
      expect(invalid_expense).not_to be_valid
      expect(invalid_expense.errors[:status]).to include('is not included in the list')
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

  describe 'associations' do
    let(:expense) { create(:expense, email_account: email_account, category: category) }

    it 'belongs to email_account' do
      expect(expense.email_account).to eq(email_account)
    end

    it 'belongs to category optionally' do
      expect(expense.category).to eq(category)

      expense_without_category = create(:expense, category: nil, email_account: email_account)
      expect(expense_without_category.category).to be_nil
    end
  end

  describe 'scopes' do
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

  describe 'scopes (additional)' do
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

  describe 'class methods' do
    let!(:expense1) { create(:expense, amount: 100, transaction_date: Time.current, email_account: email_account, category: category) }
    let!(:expense2) { create(:expense, amount: 200, transaction_date: Time.current, email_account: email_account, category: category) }
    let!(:expense3) { create(:expense, amount: 150, transaction_date: 1.month.ago, email_account: email_account, category: category) }

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

  describe 'instance methods' do
    let(:crc_expense) { create(:expense, amount: 95000, transaction_date: Time.current, email_account: email_account, currency: 'crc') }
    let(:usd_expense) { create(:expense, amount: 20.50, transaction_date: Time.current, email_account: email_account, currency: 'usd') }

    describe '#formatted_amount' do
      it 'formats CRC amounts with ₡ symbol' do
        expect(crc_expense.formatted_amount).to eq('₡95000.0')
      end

      it 'formats USD amounts with $ symbol' do
        expect(usd_expense.formatted_amount).to eq('$20.5')
      end

      it 'formats EUR amounts with € symbol' do
        eur_expense = create(:expense, amount: 15.75, transaction_date: Time.current, email_account: email_account, currency: 'eur')
        expect(eur_expense.formatted_amount).to eq('€15.75')
      end
    end

    describe '#formatted_amount' do
      it 'includes currency symbols in formatted amounts' do
        expect(crc_expense.formatted_amount).to include('₡')
        expect(usd_expense.formatted_amount).to include('$')

        eur_expense = create(:expense, amount: 15, transaction_date: Time.current, email_account: email_account, currency: 'eur')
        expect(eur_expense.formatted_amount).to include('€')
      end
    end

    describe '#duplicate?' do
      it 'returns true when status is duplicate' do
        expense = create(:expense,
          amount: 100,
          transaction_date: Time.current,
          email_account: email_account,
          status: 'duplicate'
        )

        expect(expense).to be_duplicate
      end

      it 'returns false when status is not duplicate' do
        expense = create(:expense,
          amount: 100,
          transaction_date: Time.current,
          email_account: email_account,
          status: 'pending'
        )

        expect(expense).not_to be_duplicate
      end
    end

    describe 'status helper methods' do
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

    describe '#bank_name' do
      it 'returns bank name from email account' do
        expense = create(:expense, email_account: email_account)
        expect(expense.bank_name).to eq('BAC')
      end
    end

    describe '#display_description' do
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

    describe '#parsed_email_data' do
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

    describe '#parsed_email_data=' do
      it 'sets parsed_data as JSON string' do
        expense = create(:expense, email_account: email_account)
        data = { 'amount' => '100.50', 'merchant' => 'Test Merchant' }
        expense.parsed_email_data = data
        expect(expense.parsed_data).to eq(data.to_json)
      end
    end

    describe '#category_name' do
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
end
