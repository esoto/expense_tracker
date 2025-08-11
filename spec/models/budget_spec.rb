# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Budget, type: :model do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  
  describe 'associations' do
    it { should belong_to(:email_account) }
    it { should belong_to(:category).optional }
  end

  describe 'validations' do
    subject { build(:budget, email_account: email_account) }
    
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:period) }
    
    # start_date and currency validations only on update due to before_validation callback
    context 'on update' do
      subject { create(:budget, email_account: email_account) }
      it { should validate_presence_of(:start_date).on(:update) }
      it { should validate_presence_of(:currency).on(:update) }
    end
    
    it { should validate_inclusion_of(:currency).in_array(%w[CRC USD EUR]).on(:update) }
    it { should validate_numericality_of(:warning_threshold).is_greater_than(0).is_less_than_or_equal_to(100) }
    it { should validate_numericality_of(:critical_threshold).is_greater_than(0).is_less_than_or_equal_to(100) }
    
    context 'custom validations' do
      it 'validates warning threshold is less than critical threshold' do
        budget = build(:budget, email_account: email_account, warning_threshold: 90, critical_threshold: 70)
        expect(budget).not_to be_valid
        expect(budget.errors[:warning_threshold]).to include('debe ser menor que el umbral crítico')
      end
      
      it 'validates end date is after start date' do
        budget = build(:budget, email_account: email_account, start_date: Date.current, end_date: Date.current - 1.day)
        expect(budget).not_to be_valid
        expect(budget.errors[:end_date]).to include('debe ser posterior a la fecha de inicio')
      end
      
      it 'ensures only one active budget per email_account/category/period combination' do
        create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
        duplicate = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:base]).to include('Ya existe un presupuesto activo para este período y categoría')
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:period).with_values(daily: 0, weekly: 1, monthly: 2, yearly: 3).with_prefix(true) }
  end

  describe 'scopes' do
    let!(:active_budget) { create(:budget, email_account: email_account, active: true, period: 'monthly', category: nil) }
    let!(:inactive_budget) { create(:budget, email_account: email_account, active: false, period: 'weekly', category: nil) }
    let!(:category_budget) { create(:budget, email_account: email_account, category: category, period: 'daily', active: true) }
    let!(:general_budget) { create(:budget, email_account: email_account, category: nil, period: 'yearly', active: true) }
    
    describe '.active' do
      it 'returns only active budgets' do
        expect(Budget.active).to include(active_budget)
        expect(Budget.active).not_to include(inactive_budget)
      end
    end
    
    describe '.inactive' do
      it 'returns only inactive budgets' do
        expect(Budget.inactive).to include(inactive_budget)
        expect(Budget.inactive).not_to include(active_budget)
      end
    end
    
    describe '.for_category' do
      it 'returns budgets for specific category' do
        expect(Budget.for_category(category.id)).to include(category_budget)
        expect(Budget.for_category(category.id)).not_to include(general_budget)
      end
    end
    
    describe '.general' do
      it 'returns budgets without category' do
        expect(Budget.general).to include(general_budget)
        expect(Budget.general).not_to include(category_budget)
      end
    end
  end

  describe '#current_period_range' do
    context 'for daily budget' do
      let(:budget) { build(:budget, period: 'daily') }
      
      it 'returns today\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_day)
        expect(range.end).to eq(Date.current.end_of_day)
      end
    end
    
    context 'for weekly budget' do
      let(:budget) { build(:budget, period: 'weekly') }
      
      it 'returns current week\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_week)
        expect(range.end).to eq(Date.current.end_of_week)
      end
    end
    
    context 'for monthly budget' do
      let(:budget) { build(:budget, period: 'monthly') }
      
      it 'returns current month\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_month)
        expect(range.end).to eq(Date.current.end_of_month)
      end
    end
    
    context 'for yearly budget' do
      let(:budget) { build(:budget, period: 'yearly') }
      
      it 'returns current year\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_year)
        expect(range.end).to eq(Date.current.end_of_year)
      end
    end
  end

  describe '#calculate_current_spend!' do
    let(:budget) { create(:budget, email_account: email_account, period: 'monthly', amount: 100000) }
    
    context 'with expenses in period' do
      before do
        create(:expense, email_account: email_account, amount: 25000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, amount: 30000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, amount: 20000, transaction_date: 1.month.ago, currency: 'crc') # Outside period
      end
      
      it 'calculates total spend for current period' do
        expect(budget.calculate_current_spend!).to eq(55000.0)
        expect(budget.current_spend).to eq(55000.0)
      end
      
      it 'updates current_spend_updated_at' do
        expect { budget.calculate_current_spend! }.to change { budget.current_spend_updated_at }
      end
    end
    
    context 'with category-specific budget' do
      let(:budget) { create(:budget, email_account: email_account, category: category, period: 'monthly') }
      
      before do
        create(:expense, email_account: email_account, category: category, amount: 15000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, category: nil, amount: 20000, transaction_date: Date.current, currency: 'crc')
      end
      
      it 'only counts expenses in the specified category' do
        expect(budget.calculate_current_spend!).to eq(15000.0)
      end
    end
  end

  describe '#usage_percentage' do
    let(:budget) { create(:budget, amount: 100000) }
    
    it 'returns percentage of budget used' do
      allow(budget).to receive(:current_spend_amount).and_return(75000)
      expect(budget.usage_percentage).to eq(75.0)
    end
    
    it 'handles zero budget amount' do
      budget.amount = 0
      expect(budget.usage_percentage).to eq(0.0)
    end
  end

  describe '#status' do
    let(:budget) { create(:budget, amount: 100000, warning_threshold: 70, critical_threshold: 90) }
    
    context 'when under warning threshold' do
      it 'returns :good' do
        allow(budget).to receive(:usage_percentage).and_return(50.0)
        expect(budget.status).to eq(:good)
      end
    end
    
    context 'when between warning and critical' do
      it 'returns :warning' do
        allow(budget).to receive(:usage_percentage).and_return(75.0)
        expect(budget.status).to eq(:warning)
      end
    end
    
    context 'when between critical and 100%' do
      it 'returns :critical' do
        allow(budget).to receive(:usage_percentage).and_return(95.0)
        expect(budget.status).to eq(:critical)
      end
    end
    
    context 'when exceeded' do
      it 'returns :exceeded' do
        allow(budget).to receive(:usage_percentage).and_return(110.0)
        expect(budget.status).to eq(:exceeded)
      end
    end
  end

  describe '#status_color' do
    let(:budget) { create(:budget) }
    
    it 'returns appropriate color for each status' do
      allow(budget).to receive(:status).and_return(:good)
      expect(budget.status_color).to eq('emerald-600')
      
      allow(budget).to receive(:status).and_return(:warning)
      expect(budget.status_color).to eq('amber-600')
      
      allow(budget).to receive(:status).and_return(:critical)
      expect(budget.status_color).to eq('rose-500')
      
      allow(budget).to receive(:status).and_return(:exceeded)
      expect(budget.status_color).to eq('rose-600')
    end
  end

  describe '#on_track?' do
    let(:budget) { create(:budget, period: 'monthly') }
    
    context 'when usage is below 50%' do
      it 'returns true' do
        allow(budget).to receive(:usage_percentage).and_return(40.0)
        expect(budget.on_track?).to be true
      end
    end
    
    context 'when usage exceeds time elapsed by more than 10%' do
      it 'returns false' do
        allow(budget).to receive(:usage_percentage).and_return(80.0)
        allow(budget).to receive(:period_elapsed_percentage).and_return(50.0)
        expect(budget.on_track?).to be false
      end
    end
    
    context 'when usage is within 10% buffer of time elapsed' do
      it 'returns true' do
        allow(budget).to receive(:usage_percentage).and_return(55.0)
        allow(budget).to receive(:period_elapsed_percentage).and_return(50.0)
        expect(budget.on_track?).to be true
      end
    end
  end

  describe '#duplicate_for_next_period' do
    let!(:budget) { create(:budget, email_account: email_account, period: 'monthly', start_date: Date.current.beginning_of_month, active: false) }
    
    it 'creates a new budget for the next period' do
      initial_count = Budget.count
      new_budget = budget.duplicate_for_next_period
      expect(Budget.count).to eq(initial_count + 1)
      expect(new_budget).to be_persisted
    end
    
    it 'sets correct start date for next period' do
      new_budget = budget.duplicate_for_next_period
      expect(new_budget.start_date).to eq(budget.start_date + 1.month)
    end
    
    it 'copies all relevant attributes' do
      new_budget = budget.duplicate_for_next_period
      expect(new_budget.name).to eq(budget.name)
      expect(new_budget.amount).to eq(budget.amount)
      expect(new_budget.period).to eq(budget.period)
      expect(new_budget.warning_threshold).to eq(budget.warning_threshold)
    end
  end

  describe '#deactivate!' do
    let(:budget) { create(:budget, active: true) }
    
    it 'sets active to false' do
      budget.deactivate!
      expect(budget.reload.active).to be false
    end
  end

  describe 'callbacks' do
    describe 'after_create' do
      let(:budget) { build(:budget, email_account: email_account) }
      
      it 'calculates current spend after creation' do
        expect(budget).to receive(:calculate_current_spend_after_save)
        budget.save!
      end
    end
  end

  describe '#formatted_amount' do
    let(:budget) { build(:budget, amount: 125000, currency: 'CRC') }
    
    it 'formats amount with currency symbol' do
      expect(budget.formatted_amount).to include('₡')
      expect(budget.formatted_amount).to include('125')
    end
  end

  describe '#currency_symbol' do
    it 'returns correct symbol for each currency' do
      budget = build(:budget, currency: 'CRC')
      expect(budget.currency_symbol).to eq('₡')
      
      budget.currency = 'USD'
      expect(budget.currency_symbol).to eq('$')
      
      budget.currency = 'EUR'
      expect(budget.currency_symbol).to eq('€')
    end
  end
end