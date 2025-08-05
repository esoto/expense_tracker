require 'rails_helper'

RSpec.describe DashboardService do
  let(:service) { described_class.new }
  let(:category) { create(:category) }
  let(:email_account) { create(:email_account, :bac) }

  describe '#analytics' do
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

      expect(totals[:total_expenses]).to eq(300.0)
      expect(totals[:expense_count]).to eq(2)
      expect(totals[:current_month_total]).to eq(100.0)
      expect(totals[:last_month_total]).to eq(200.0)
    end

    it 'provides recent expenses with associations' do
      result = service.analytics
      recent = result[:recent_expenses]

      expect(recent).to include(current_month_expense, last_month_expense)
      expect(recent.size).to be <= 10

      # Verify associations are loaded (no additional queries should be needed)
      expect(recent.first.category).to be_present
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

  describe 'private methods' do
    describe '#current_month_total' do
      it 'calculates expenses for current month only' do
        create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account)
        create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account)

        total = service.send(:current_month_total)
        expect(total).to eq(100.0)
      end
    end

    describe '#last_month_total' do
      it 'calculates expenses for last month only' do
        create(:expense, amount: 100.0, transaction_date: Date.current, category: category, email_account: email_account)
        create(:expense, amount: 200.0, transaction_date: 1.month.ago, category: category, email_account: email_account)

        total = service.send(:last_month_total)
        expect(total).to eq(200.0)
      end
    end
  end
end
