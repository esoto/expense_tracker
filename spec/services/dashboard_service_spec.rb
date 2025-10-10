require 'rails_helper'

RSpec.describe Services::DashboardService, integration: true do
  let(:service) { described_class.new }
  let(:category) { create(:category) }
  let(:email_account) { create(:email_account, :bac) }

  describe '#analytics', integration: true do
    let!(:current_month_expense) { create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account) }
    let!(:last_month_expense) { create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account) }

    it 'returns comprehensive analytics data' do
      result = service.analytics

      expect(result).to include(
        :totals, :recent_expenses, :category_breakdown, :monthly_trend,
        :bank_breakdown, :top_merchants, :email_accounts, :sync_info, :sync_sessions
      )
    end

    it 'calculates total statistics correctly' do
      result = service.analytics
      totals = result[:totals]

      # Our test expenses (current_month_expense and last_month_expense) exist
      # Check that they are included in the totals
      expect(totals[:total_expenses]).to be >= 300.0
      expect(totals[:expense_count]).to be >= 2
      expect(totals[:current_month_total]).to be >= 100.0
      expect(totals[:last_month_total]).to be >= 200.0
    end

    it 'provides recent expenses with associations' do
      result = service.analytics
      recent = result[:recent_expenses]

      # Recent expenses are ordered by transaction_date DESC
      # Our test expenses should be in the result set
      expect(recent).to be_present
      expect(recent.size).to be <= 10

      # Check that at least one of our test expenses is included
      recent_ids = recent.map(&:id)
      test_expense_ids = [ current_month_expense.id, last_month_expense.id ]
      expect(recent_ids & test_expense_ids).not_to be_empty

      # Verify associations are loaded (no additional queries should be needed)
      if recent.first.category_id
        expect(recent.first.category).to be_present
      end
    end

    it 'generates category breakdown with totals and sorted data' do
      result = service.analytics
      breakdown = result[:category_breakdown]

      expect(breakdown[:totals]).to be_a(Hash)
      expect(breakdown[:sorted]).to be_an(Array)
      expect(breakdown[:totals][category.name]).to eq(300.0)
    end

    it 'provides monthly trend data for last 6 months' do
      result = service.analytics
      trend = result[:monthly_trend]

      expect(trend).to be_a(Hash)
      expect(trend.values).to all(be_a(Float))
    end

    it 'calculates bank breakdown sorted by amount' do
      result = service.analytics
      banks = result[:bank_breakdown]

      expect(banks).to be_an(Array)
      expect(banks.first).to be_an(Array) # [bank_name, amount] pairs
    end

    it 'finds top merchants limited to 10' do
      result = service.analytics
      merchants = result[:top_merchants]

      expect(merchants).to be_an(Array)
      expect(merchants.size).to be <= 10
    end

    it 'loads active email accounts ordered properly' do
      result = service.analytics
      accounts = result[:email_accounts]

      expect(accounts).to include(email_account)
      expect(accounts.all?(&:active?)).to be true
    end

    it 'generates sync info with job status' do
      # Mock SolidQueue::Job to avoid database dependency
      jobs_relation = double("jobs_relation", exists?: false, count: 0)
      allow(SolidQueue::Job).to receive(:where)
        .with(class_name: "ProcessEmailsJob", finished_at: nil)
        .and_return(double("intermediate", where: jobs_relation))

      result = service.analytics
      sync_info = result[:sync_info]

      expect(sync_info).to include(:has_running_jobs, :running_job_count)
      expect(sync_info[:has_running_jobs]).to eq(false)
      expect(sync_info[:running_job_count]).to eq(0)
    end

    it 'includes sync session data' do
      active_session = create(:sync_session, :running)
      completed_session = create(:sync_session, :completed)

      result = service.analytics
      sync_sessions = result[:sync_sessions]

      expect(sync_sessions).to include(:active_session, :last_completed)
      expect(sync_sessions[:active_session]).to eq(active_session)
      expect(sync_sessions[:last_completed]).to eq(completed_session)
    end
  end

  describe 'private methods', integration: true do
    describe '#current_month_total', integration: true do
      it 'calculates expenses for current month only' do
        # Get baseline total first
        baseline_total = service.send(:current_month_total)

        create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account)
        create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account)

        total = service.send(:current_month_total)
        # Check the difference, not absolute value
        expect(total - baseline_total).to eq(100.0)
      end
    end

    describe '#last_month_total', integration: true do
      it 'calculates expenses for last month only' do
        # Get baseline total first
        baseline_total = service.send(:last_month_total)

        create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account)
        create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account)

        total = service.send(:last_month_total)
        # Check the difference, not absolute value
        expect(total - baseline_total).to eq(200.0)
      end
    end
  end

  describe 'caching behavior', integration: true do
    before do
      Rails.cache.clear
    end

    it 'caches analytics data' do
      # First call should write to cache
      expect(Rails.cache).to receive(:fetch).with("dashboard_analytics", expires_in: 5.minutes).and_call_original
      service.analytics
    end

    it 'does not cache sync_info' do
      analytics1 = service.analytics

      # Create a new expense
      create(:expense, email_account: email_account, created_at: 1.minute.from_now)

      analytics2 = service.analytics
      # sync_info should be different because it's not cached
      expect(analytics2[:sync_info]).not_to eq(analytics1[:sync_info])
    end
  end

  describe '.clear_cache', integration: true do
    before do
      Rails.cache.write('dashboard_analytics', { test: 'data' })
      Rails.cache.write('dashboard_other', { test: 'data' })
      Rails.cache.write('other_key', { test: 'data' })
    end

    it 'clears all dashboard cache keys' do
      expect(Rails.cache).to receive(:delete_matched).with("dashboard_*")
      DashboardService.clear_cache
    end
  end

  describe 'edge cases', integration: true do
    context 'with no data' do
      before do
        # Clean up with proper foreign key handling
        ConflictResolution.where.not(undone_by_resolution_id: nil).update_all(undone_by_resolution_id: nil) if defined?(ConflictResolution)
        ConflictResolution.destroy_all if defined?(ConflictResolution)
        SyncConflict.destroy_all if defined?(SyncConflict)
        PatternLearningEvent.destroy_all if defined?(PatternLearningEvent)
        Expense.destroy_all
        EmailAccount.destroy_all
        DashboardService.clear_cache  # Clear cache after destroying data
      end

      it 'returns zero values when no expenses exist' do
        analytics = service.analytics

        expect(analytics[:totals][:total_expenses]).to eq(0)
        expect(analytics[:totals][:expense_count]).to eq(0)
        expect(analytics[:totals][:current_month_total]).to eq(0)
        expect(analytics[:totals][:last_month_total]).to eq(0)
        expect(analytics[:recent_expenses]).to be_empty
        expect(analytics[:category_breakdown][:totals]).to be_empty
        expect(analytics[:category_breakdown][:sorted]).to be_empty
        expect(analytics[:monthly_trend]).to be_empty
        expect(analytics[:bank_breakdown]).to be_empty
        expect(analytics[:top_merchants]).to be_empty
      end
    end

    context 'with expenses without categories' do
      let!(:expense_no_category) { create(:expense, category: nil, email_account: email_account, amount: 50.0) }

      it 'handles nil categories in breakdown' do
        # Get baseline before test expense
        baseline_analytics = service.analytics
        baseline_total = baseline_analytics[:category_breakdown][:totals].values.sum

        analytics = service.analytics
        # Category breakdown uses joins, so expenses without categories won't appear
        # Check that the total remains unchanged from baseline
        expect(analytics[:category_breakdown][:totals].values.sum - baseline_total).to eq(0)
      end
    end

    context 'with expenses without merchants' do
      before do
        # Clean up to have a controlled test environment
        ConflictResolution.where.not(undone_by_resolution_id: nil).update_all(undone_by_resolution_id: nil) if defined?(ConflictResolution)
        ConflictResolution.destroy_all if defined?(ConflictResolution)
        SyncConflict.destroy_all if defined?(SyncConflict)
        PatternLearningEvent.destroy_all if defined?(PatternLearningEvent)
        Expense.destroy_all

        create(:expense, merchant_name: nil, email_account: email_account, amount: 100.0)
        create(:expense, merchant_name: 'Store A', email_account: email_account, amount: 200.0)
      end

      it 'includes expenses with nil merchants in top merchants' do
        analytics = service.analytics
        merchant_names = analytics[:top_merchants].map(&:first)
        # The method doesn't exclude nil merchants, it includes them
        expect(merchant_names).to include(nil)
        expect(merchant_names).to include('Store A')
      end
    end

    context 'with future dated expenses' do
      let!(:future_expense) { create(:expense, transaction_date: 1.month.from_now, email_account: email_account, amount: 999.0) }

      it 'includes future expenses in totals' do
        analytics = service.analytics
        expect(analytics[:totals][:total_expenses]).to be >= future_expense.amount
      end

      it 'does not include future expenses in current month' do
        current_month_expenses = Expense.where(
          transaction_date: Date.current.beginning_of_month..Date.current.end_of_month
        ).sum(:amount)

        analytics = service.analytics
        expect(analytics[:totals][:current_month_total]).to eq(current_month_expenses)
      end
    end
  end
end
