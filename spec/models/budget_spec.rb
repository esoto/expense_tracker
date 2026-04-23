# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Budget, type: :model, integration: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }

  describe 'associations', integration: true do
    it { should belong_to(:user) }
    it { should belong_to(:email_account) }
    it { should belong_to(:category).optional }
  end

  describe '.for_user scope', unit: true do
    let!(:user_a) { create(:user) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:account_b) { create(:email_account, user: user_b) }
    let!(:budget_a) { create(:budget, user: user_a, email_account: account_a) }
    let!(:budget_b) { create(:budget, user: user_b, email_account: account_b) }

    it 'returns only budgets belonging to the given user' do
      expect(Budget.for_user(user_a)).to contain_exactly(budget_a)
    end

    it 'excludes budgets belonging to other users' do
      expect(Budget.for_user(user_a)).not_to include(budget_b)
    end
  end

  describe 'validations', integration: true do
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

      it 'allows two general (category-less) budgets in the same period — overlap is allowed by design' do
        # Rationale: multi-category budgets can intentionally claim the same categories across
        # budgets (e.g., "Familia" and "Esteban" both covering Food). Uniqueness on the legacy
        # category_id column is obsolete under the new M2M routing. Dup-blocking is still enforced
        # for external-source budgets (see #unique_active_budget_per_scope with external sources).
        create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
        duplicate = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
        expect(duplicate).to be_valid
      end
    end
  end

  describe 'enums', integration: true do
    it { should define_enum_for(:period).with_values(daily: 0, weekly: 1, monthly: 2, yearly: 3).with_prefix(true) }
  end

  describe 'scopes', integration: true do
    let!(:active_budget) { create(:budget, email_account: email_account, active: true, period: 'monthly', category: nil) }
    let!(:inactive_budget) { create(:budget, email_account: email_account, active: false, period: 'weekly', category: nil) }
    let!(:category_budget) { create(:budget, email_account: email_account, category: category, period: 'daily', active: true) }
    let!(:general_budget) { create(:budget, email_account: email_account, category: nil, period: 'yearly', active: true) }

    describe '.active', integration: true do
      it 'returns only active budgets' do
        expect(Budget.active).to include(active_budget)
        expect(Budget.active).not_to include(inactive_budget)
      end
    end

    describe '.inactive', integration: true do
      it 'returns only inactive budgets' do
        expect(Budget.inactive).to include(inactive_budget)
        expect(Budget.inactive).not_to include(active_budget)
      end
    end

    describe '.for_category', integration: true do
      it 'returns budgets for specific category' do
        expect(Budget.for_category(category.id)).to include(category_budget)
        expect(Budget.for_category(category.id)).not_to include(general_budget)
      end
    end

    describe '.general', integration: true do
      it 'returns budgets without category' do
        expect(Budget.general).to include(general_budget)
        expect(Budget.general).not_to include(category_budget)
      end
    end
  end

  describe '#current_period_range', integration: true do
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
        expect(range.begin).to eq(Date.current.beginning_of_week.beginning_of_day)
        expect(range.end).to eq(Date.current.end_of_week.end_of_day)
      end
    end

    context 'for monthly budget' do
      let(:budget) { build(:budget, period: 'monthly') }

      it 'returns current month\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_month.beginning_of_day)
        expect(range.end).to eq(Date.current.end_of_month.end_of_day)
      end
    end

    context 'for yearly budget' do
      let(:budget) { build(:budget, period: 'yearly') }

      it 'returns current year\'s date range' do
        range = budget.current_period_range
        expect(range.begin).to eq(Date.current.beginning_of_year.beginning_of_day)
        expect(range.end).to eq(Date.current.end_of_year.end_of_day)
      end
    end
  end

  describe '#calculate_current_spend!', integration: true do
    # NOTE: Comprehensive unit-style coverage of spend calc rules (override,
    # M2M routing, overlap, empty budgets) lives in
    # spec/models/budget_spend_calculation_spec.rb. Tests below exercise the
    # full DB persistence + cache-update path as an integration smoke.

    let(:budget) do
      b = create(:budget, email_account: email_account, period: 'monthly', amount: 100000)
      b.categories << category
      b
    end

    context 'with expenses in period' do
      before do
        create(:expense, email_account: email_account, category: category, amount: 25000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, category: category, amount: 30000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, category: category, amount: 20000, transaction_date: 1.month.ago, currency: 'crc') # Outside period
      end

      it 'calculates total spend for current period' do
        expect(budget.calculate_current_spend!).to eq(55000.0)
        expect(budget.current_spend).to eq(55000.0)
      end

      it 'updates current_spend_updated_at' do
        expect { budget.calculate_current_spend! }.to change { budget.current_spend_updated_at }
      end
    end

    context 'with a claimed category' do
      before do
        create(:expense, email_account: email_account, category: category, amount: 15000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, category: nil, amount: 20000, transaction_date: Date.current, currency: 'crc')
      end

      it 'only counts expenses in a claimed category' do
        expect(budget.calculate_current_spend!).to eq(15000.0)
      end
    end
  end

  describe '#usage_percentage', integration: true do
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

  describe '#status', integration: true do
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

  describe '#status_color', integration: true do
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

  describe '#on_track?', integration: true do
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

  describe '#duplicate_for_next_period', integration: true do
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

  describe '#deactivate!', integration: true do
    let(:budget) { create(:budget, active: true) }

    it 'sets active to false' do
      budget.deactivate!
      expect(budget.reload.active).to be false
    end
  end

  describe 'callbacks', integration: true do
    describe 'after_create', integration: true do
      let(:budget) { build(:budget, email_account: email_account) }

      it 'calculates current spend after creation' do
        expect(budget).to receive(:calculate_current_spend_after_save)
        budget.save!
      end
    end
  end

  describe '#formatted_amount', integration: true do
    let(:budget) { build(:budget, amount: 125000, currency: 'CRC') }

    it 'formats amount with currency symbol' do
      expect(budget.formatted_amount).to include('₡')
      expect(budget.formatted_amount).to include('125')
    end
  end

  describe '#currency_symbol', integration: true do
    it 'returns correct symbol for each currency' do
      budget = build(:budget, currency: 'CRC')
      expect(budget.currency_symbol).to eq('₡')

      budget.currency = 'USD'
      expect(budget.currency_symbol).to eq('$')

      budget.currency = 'EUR'
      expect(budget.currency_symbol).to eq('€')
    end
  end

  describe '.external', unit: true do
    it 'returns only budgets with an external_source' do
      native = create(:budget, email_account: email_account, category: nil, period: 'monthly')
      external = create(:budget, email_account: email_account, category: category, period: 'weekly',
                                 external_source: 'salary_calculator', external_id: 101)

      expect(described_class.external).to include(external)
      expect(described_class.external).not_to include(native)
    end
  end

  describe '.native', unit: true do
    it 'returns only budgets without an external_source' do
      native = create(:budget, email_account: email_account, category: nil, period: 'monthly')
      external = create(:budget, email_account: email_account, category: category, period: 'weekly',
                                 external_source: 'salary_calculator', external_id: 102)

      expect(described_class.native).to include(native)
      expect(described_class.native).not_to include(external)
    end
  end

  describe '.synced_unmapped', unit: true do
    it 'returns only external budgets with no category' do
      native = create(:budget, email_account: email_account, category: nil, period: 'monthly')
      external_mapped = create(:budget, email_account: email_account, category: category, period: 'weekly',
                                        external_source: 'salary_calculator', external_id: 103)
      external_unmapped = create(:budget, email_account: email_account, category: nil, period: 'yearly',
                                          external_source: 'salary_calculator', external_id: 104)

      results = described_class.synced_unmapped
      expect(results).to include(external_unmapped)
      expect(results).not_to include(native, external_mapped)
    end
  end

  describe 'unique_active_budget_per_scope with external sources', integration: true do
    it 'allows an unmapped external budget to coexist with a native category-less budget in same period' do
      create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
      external = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true,
                                external_source: 'salary_calculator', external_id: 301)

      expect(external).to be_valid
    end

    it 'allows two external budgets with different external_ids in same period/category' do
      create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true,
                      external_source: 'salary_calculator', external_id: 401)
      second = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true,
                              external_source: 'salary_calculator', external_id: 402)

      expect(second).to be_valid
    end

    it 'rejects a duplicate external budget with the same external_source + external_id' do
      create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true,
                      external_source: 'salary_calculator', external_id: 501)
      duplicate = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true,
                                 external_source: 'salary_calculator', external_id: 501)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include('Ya existe un presupuesto activo para este período y categoría')
    end

    it 'allows two native general budgets in the same period — overlap is allowed by design' do
      # Under multi-category budgets, two general (category-less) budgets in the same
      # email_account + period can legitimately coexist. Dup-blocking only applies to
      # external-source budgets (keyed by external_source + external_id).
      create(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)
      duplicate = build(:budget, email_account: email_account, category: nil, period: 'monthly', active: true)

      expect(duplicate).to be_valid
    end
  end

  describe '#external?', unit: true do
    it 'is true when external_source is present' do
      budget = build(:budget, external_source: 'salary_calculator')
      expect(budget.external?).to be(true)
    end

    it 'is false when external_source is nil' do
      budget = build(:budget, external_source: nil)
      expect(budget.external?).to be(false)
    end
  end

  describe '#unmapped?', unit: true do
    it 'is true when external and category is nil' do
      budget = build(:budget, external_source: 'salary_calculator', category: nil)
      expect(budget.unmapped?).to be(true)
    end

    it 'is false when external and a category is set' do
      budget = build(:budget, external_source: 'salary_calculator', category: category)
      expect(budget.unmapped?).to be(false)
    end

    it 'is false when native (no external_source) even without a category' do
      budget = build(:budget, external_source: nil, category: nil)
      expect(budget.unmapped?).to be(false)
    end
  end

  describe '#calculate_current_spend!', unit: true do
    context 'for an unmapped external budget' do
      let(:budget) do
        create(:budget,
               email_account: email_account,
               category: nil,
               period: 'monthly',
               active: true,
               external_source: 'salary_calculator',
               external_id: 201)
      end

      it 'returns 0.0 without querying expenses' do
        expect(email_account.expenses).not_to receive(:includes)
        expect(budget.calculate_current_spend!).to eq(0.0)
      end

      it 'stamps current_spend to 0.0 and sets current_spend_updated_at' do
        freeze_at = Time.current
        travel_to(freeze_at) do
          budget.calculate_current_spend!
        end

        budget.reload
        expect(budget.current_spend).to eq(0.0)
        expect(budget.current_spend_updated_at).to be_within(1.second).of(freeze_at)
      end

      it 'avoids recomputing on subsequent current_spend_amount calls within the cache TTL' do
        budget.calculate_current_spend!

        expect(budget).not_to receive(:calculate_current_spend!)
        expect(budget.current_spend_amount).to eq(0.0)
      end
    end
  end
end
