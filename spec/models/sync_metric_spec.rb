require 'rails_helper'

RSpec.describe SyncMetric, type: :model do
  # Associations
  describe 'associations' do
    it { should belong_to(:sync_session) }
    it { should belong_to(:email_account).optional }
  end

  # Validations
  describe 'validations' do
    it { should validate_presence_of(:metric_type) }
    it { should validate_presence_of(:started_at) }

    it do
      should validate_inclusion_of(:metric_type)
        .in_array(SyncMetric::METRIC_TYPES.values)
    end

    it { should validate_numericality_of(:duration).is_greater_than_or_equal_to(0).allow_nil }
    it { should validate_numericality_of(:emails_processed).is_greater_than_or_equal_to(0) }
  end

  # Scopes
  describe 'scopes' do
    let!(:sync_session) { create(:sync_session) }
    let!(:email_account) { create(:email_account) }
    let!(:successful_metric) { create(:sync_metric, sync_session: sync_session, success: true) }
    let!(:failed_metric) { create(:sync_metric, sync_session: sync_session, success: false) }
    let!(:old_metric) { create(:sync_metric, sync_session: sync_session, started_at: 2.days.ago) }
    let!(:recent_metric) { create(:sync_metric, sync_session: sync_session, started_at: 1.hour.ago) }

    describe '.successful' do
      it 'returns only successful metrics' do
        expect(SyncMetric.successful).to include(successful_metric)
        expect(SyncMetric.successful).not_to include(failed_metric)
      end
    end

    describe '.failed' do
      it 'returns only failed metrics' do
        expect(SyncMetric.failed).to include(failed_metric)
        expect(SyncMetric.failed).not_to include(successful_metric)
      end
    end

    describe '.by_type' do
      let!(:fetch_metric) { create(:sync_metric, sync_session: sync_session, metric_type: 'email_fetch') }
      let!(:parse_metric) { create(:sync_metric, sync_session: sync_session, metric_type: 'email_parse') }

      it 'returns metrics of the specified type' do
        expect(SyncMetric.by_type('email_fetch')).to include(fetch_metric)
        expect(SyncMetric.by_type('email_fetch')).not_to include(parse_metric)
      end
    end

    describe '.recent' do
      it 'returns metrics ordered by started_at desc' do
        results = SyncMetric.recent
        expect(results.map(&:started_at)).to eq(results.map(&:started_at).sort.reverse)
        expect(results).to include(recent_metric, old_metric)
      end
    end

    describe '.last_24_hours' do
      it 'returns metrics from the last 24 hours' do
        expect(SyncMetric.last_24_hours).to include(recent_metric)
        expect(SyncMetric.last_24_hours).not_to include(old_metric)
      end
    end
  end

  # Callbacks
  describe 'callbacks' do
    describe '#calculate_duration' do
      let(:sync_session) { create(:sync_session) }

      context 'when completed_at and started_at are present' do
        it 'calculates duration in milliseconds' do
          metric = SyncMetric.new(
            sync_session: sync_session,
            metric_type: 'email_fetch',
            started_at: Time.current,
            completed_at: Time.current + 5.seconds
          )

          metric.save!
          expect(metric.duration).to be_within(10).of(5000) # 5 seconds = 5000ms
        end
      end

      context 'when duration is already set' do
        it 'does not overwrite existing duration' do
          metric = SyncMetric.new(
            sync_session: sync_session,
            metric_type: 'email_fetch',
            started_at: Time.current,
            completed_at: Time.current + 5.seconds,
            duration: 3000
          )

          metric.save!
          expect(metric.duration).to eq(3000)
        end
      end
    end
  end

  # Class methods
  describe 'class methods' do
    let!(:sync_session) { create(:sync_session) }

    before do
      # Create test data
      create(:sync_metric,
        sync_session: sync_session,
        metric_type: 'email_fetch',
        success: true,
        duration: 1000,
        started_at: 1.hour.ago
      )
      create(:sync_metric,
        sync_session: sync_session,
        metric_type: 'email_fetch',
        success: false,
        duration: 2000,
        started_at: 2.hours.ago
      )
      create(:sync_metric,
        sync_session: sync_session,
        metric_type: 'email_parse',
        success: true,
        duration: 500,
        started_at: 30.minutes.ago
      )
    end

    describe '.average_duration_by_type' do
      it 'returns average duration for each metric type' do
        averages = SyncMetric.average_duration_by_type(:last_24_hours)

        expect(averages['email_fetch']).to eq(1500.0)
        expect(averages['email_parse']).to eq(500.0)
      end
    end

    describe '.success_rate_by_type' do
      it 'returns success rate percentage for each metric type' do
        rates = SyncMetric.success_rate_by_type(:last_24_hours)

        expect(rates['email_fetch']).to eq(50.0)
        expect(rates['email_parse']).to eq(100.0)
      end
    end

    describe '.error_distribution' do
      before do
        create(:sync_metric,
          sync_session: sync_session,
          success: false,
          error_type: 'ConnectionError',
          started_at: 1.hour.ago
        )
        create(:sync_metric,
          sync_session: sync_session,
          success: false,
          error_type: 'ConnectionError',
          started_at: 2.hours.ago
        )
        create(:sync_metric,
          sync_session: sync_session,
          success: false,
          error_type: 'ParseError',
          started_at: 3.hours.ago
        )
      end

      it 'returns error types sorted by frequency' do
        distribution = SyncMetric.error_distribution(:last_24_hours)

        expect(distribution.keys.first).to eq('ConnectionError')
        expect(distribution['ConnectionError']).to eq(2)
        expect(distribution['ParseError']).to eq(1)
      end
    end

    describe '.peak_hours' do
      before do
        # Create metrics at different hours within the last 7 days
        create(:sync_metric, sync_session: sync_session, started_at: 2.days.ago.beginning_of_day + 9.hours)
        create(:sync_metric, sync_session: sync_session, started_at: 2.days.ago.beginning_of_day + 9.hours + 10.minutes)
        create(:sync_metric, sync_session: sync_session, started_at: 1.day.ago.beginning_of_day + 14.hours)
      end

      it 'returns hours sorted by activity count' do
        peak_times = SyncMetric.peak_hours(:last_7_days)

        expect(peak_times).to be_a(Hash)
        expect(peak_times.keys).not_to be_empty
        expect(peak_times.values.first).to be >= peak_times.values.last if peak_times.count > 1
      end
    end

    describe '.account_performance_summary' do
      let!(:email_account1) { create(:email_account, bank_name: 'BAC', email: 'test1@example.com') }
      let!(:email_account2) { create(:email_account, bank_name: 'BCR', email: 'test2@example.com') }

      before do
        # Create account sync metrics for different accounts
        create(:sync_metric,
          sync_session: sync_session,
          email_account: email_account1,
          metric_type: 'account_sync',
          success: true,
          duration: 1000,
          emails_processed: 5,
          started_at: 1.hour.ago
        )
        create(:sync_metric,
          sync_session: sync_session,
          email_account: email_account1,
          metric_type: 'account_sync',
          success: false,
          duration: 2000,
          emails_processed: 3,
          started_at: 2.hours.ago
        )
        create(:sync_metric,
          sync_session: sync_session,
          email_account: email_account2,
          metric_type: 'account_sync',
          success: true,
          duration: 1500,
          emails_processed: 10,
          started_at: 30.minutes.ago
        )
      end

      it 'returns performance data for all active accounts' do
        summary = SyncMetric.account_performance_summary(:last_24_hours)

        expect(summary).to be_an(Array)
        expect(summary.count).to eq(EmailAccount.active.count)

        # Find summaries for our test accounts
        account1_summary = summary.find { |s| s[:account_id] == email_account1.id }
        account2_summary = summary.find { |s| s[:account_id] == email_account2.id }

        expect(account1_summary).to include(
          account_id: email_account1.id,
          bank_name: 'BAC',
          email: 'test1@example.com',
          total_syncs: 2,
          success_rate: 50.0,
          emails_processed: 8
        )

        expect(account2_summary).to include(
          account_id: email_account2.id,
          bank_name: 'BCR',
          email: 'test2@example.com',
          total_syncs: 1,
          success_rate: 100.0,
          emails_processed: 10
        )
      end

      it 'handles accounts with no metrics' do
        account_without_metrics = create(:email_account, bank_name: 'BNCR', email: 'test3@example.com')
        summary = SyncMetric.account_performance_summary(:last_24_hours)

        account_summary = summary.find { |s| s[:account_id] == account_without_metrics.id }
        expect(account_summary).to include(
          total_syncs: 0,
          success_rate: 0.0,
          emails_processed: 0
        )
      end
    end

    describe '.hourly_performance' do
      before do
        create(:sync_metric,
          sync_session: sync_session,
          metric_type: 'email_fetch',
          success: true,
          started_at: 2.hours.ago
        )
        create(:sync_metric,
          sync_session: sync_session,
          metric_type: 'email_fetch',
          success: false,
          started_at: 1.hour.ago
        )
      end

      it 'returns hourly performance data' do
        performance = SyncMetric.hourly_performance('email_fetch', 24)

        expect(performance).to be_a(Hash)
        expect(performance.keys).to all(be_an(Array))
        expect(performance.values).to all(be_a(Integer))
      end

      it 'filters by metric type when specified' do
        performance_all = SyncMetric.hourly_performance(nil, 24)
        performance_fetch = SyncMetric.hourly_performance('email_fetch', 24)

        expect(performance_fetch.values.sum).to be <= performance_all.values.sum
      end
    end
  end

  # Instance methods
  describe 'instance methods' do
    let(:sync_session) { create(:sync_session) }

    describe '#duration_in_seconds' do
      it 'converts duration from milliseconds to seconds' do
        metric = create(:sync_metric, sync_session: sync_session, duration: 5500)
        expect(metric.duration_in_seconds).to eq(5.5)
      end

      it 'returns nil when duration is nil' do
        metric = create(:sync_metric, sync_session: sync_session, duration: nil)
        expect(metric.duration_in_seconds).to be_nil
      end
    end

    describe '#processing_rate' do
      context 'with valid data' do
        it 'calculates emails per second' do
          metric = create(:sync_metric,
            sync_session: sync_session,
            duration: 5000,
            emails_processed: 10
          )
          expect(metric.processing_rate).to eq(2.0)
        end
      end

      context 'with zero duration' do
        it 'returns nil' do
          metric = create(:sync_metric,
            sync_session: sync_session,
            duration: 0,
            emails_processed: 10
          )
          expect(metric.processing_rate).to be_nil
        end
      end

      context 'with zero emails processed' do
        it 'returns nil' do
          metric = create(:sync_metric,
            sync_session: sync_session,
            duration: 5000,
            emails_processed: 0
          )
          expect(metric.processing_rate).to be_nil
        end
      end
    end

    describe '#status_badge' do
      it 'returns success for successful metrics' do
        metric = create(:sync_metric, sync_session: sync_session, success: true)
        expect(metric.status_badge).to eq('success')
      end

      it 'returns error for failed metrics' do
        metric = create(:sync_metric, sync_session: sync_session, success: false)
        expect(metric.status_badge).to eq('error')
      end
    end
  end
end
