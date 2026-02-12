# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FailedBroadcastStore, type: :model, integration: true do
  include ActiveSupport::Testing::TimeHelpers
  let(:sync_session) { create(:sync_session) }

  describe 'validations', integration: true do
    subject { build(:failed_broadcast_store) }

    it { should validate_presence_of(:channel_name) }
    it { should validate_presence_of(:target_type) }
    it { should validate_presence_of(:target_id) }
    # Data is ensured to be present via before_validation callback
    it { should validate_presence_of(:priority) }
    it { should validate_presence_of(:error_type) }
    it { should validate_presence_of(:error_message) }
    it { should validate_presence_of(:failed_at) }
    it { should validate_presence_of(:retry_count) }

    it { should validate_numericality_of(:target_id).is_greater_than(0) }
    it { should validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0) }

    it { should validate_inclusion_of(:priority).in_array(described_class::PRIORITIES) }
    it { should validate_inclusion_of(:error_type).in_array(described_class::ERROR_TYPES) }

    it 'validates uniqueness of sidekiq_job_id when present' do
      create(:failed_broadcast_store, sidekiq_job_id: 'unique_job_id')
      duplicate = build(:failed_broadcast_store, sidekiq_job_id: 'unique_job_id')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:sidekiq_job_id]).to include('has already been taken')
    end

    it 'allows nil sidekiq_job_id' do
      record = build(:failed_broadcast_store, sidekiq_job_id: nil)
      expect(record).to be_valid
    end

    it 'validates priority values' do
      described_class::PRIORITIES.each do |priority|
        record = build(:failed_broadcast_store, priority: priority)
        expect(record).to be_valid
      end

      invalid_record = build(:failed_broadcast_store, priority: 'invalid')
      expect(invalid_record).not_to be_valid
    end

    it 'validates error_type values' do
      described_class::ERROR_TYPES.each do |error_type|
        record = build(:failed_broadcast_store, error_type: error_type)
        expect(record).to be_valid
      end

      invalid_record = build(:failed_broadcast_store, error_type: 'invalid')
      expect(invalid_record).not_to be_valid
    end
  end

  describe 'scopes', integration: true do
    let!(:unrecovered_record) { create(:failed_broadcast_store, failed_at: 10.minutes.ago) }
    let!(:recovered_record) { create(:failed_broadcast_store, :recovered, failed_at: 30.minutes.ago) }
    let!(:critical_record) { create(:failed_broadcast_store, :critical_priority, failed_at: 20.minutes.ago) }
    let!(:old_record) { create(:failed_broadcast_store, failed_at: 2.days.ago) }

    describe '.unrecovered', integration: true do
      it 'returns only unrecovered records' do
        expect(described_class.unrecovered).to include(unrecovered_record, critical_record, old_record)
        expect(described_class.unrecovered).not_to include(recovered_record)
      end
    end

    describe '.recovered', integration: true do
      it 'returns only recovered records' do
        expect(described_class.recovered).to include(recovered_record)
        expect(described_class.recovered).not_to include(unrecovered_record, critical_record, old_record)
      end
    end

    describe '.by_priority', integration: true do
      it 'filters by priority level' do
        expect(described_class.by_priority('critical')).to include(critical_record)
        expect(described_class.by_priority('critical')).not_to include(unrecovered_record)
      end
    end

    describe '.by_channel', integration: true do
      it 'filters by channel name' do
        expect(described_class.by_channel('SyncStatusChannel')).to include(unrecovered_record)
      end
    end

    describe '.by_error_type', integration: true do
      it 'filters by error type' do
        expect(described_class.by_error_type('connection_timeout')).to include(unrecovered_record)
        expect(described_class.by_error_type('job_death')).to include(critical_record)
      end
    end

    describe '.recent_failures', integration: true do
      it 'orders by failed_at descending' do
        expect(described_class.recent_failures.first).to eq(unrecovered_record)
        expect(described_class.recent_failures.last).to eq(old_record)
      end
    end

    describe '.ready_for_retry', integration: true do
      let!(:max_retries_record) { create(:failed_broadcast_store, :max_retries_reached) }

      it 'includes unrecovered records with retry attempts remaining' do
        expect(described_class.ready_for_retry).to include(unrecovered_record)
        expect(described_class.ready_for_retry).not_to include(recovered_record, max_retries_record)
      end
    end
  end

  describe '.max_retry_attempts', integration: true do
    it 'returns correct retry attempts for each priority' do
      expect(described_class.max_retry_attempts('critical')).to eq(5)
      expect(described_class.max_retry_attempts('high')).to eq(4)
      expect(described_class.max_retry_attempts('medium')).to eq(3)
      expect(described_class.max_retry_attempts('low')).to eq(2)
      expect(described_class.max_retry_attempts('unknown')).to eq(3)
    end
  end

  describe '.create_from_job_failure!', integration: true do
    let(:job_data) do
      {
        'args' => [ 'SyncStatusChannel', sync_session.id, 'SyncSession', { status: 'processing' }, 'high' ],
        'retry_count' => 2,
        'jid' => 'job123'
      }
    end
    let(:error) { ActiveRecord::RecordNotFound.new("Record not found") }

    it 'creates failed broadcast from job data' do
      record = described_class.create_from_job_failure!(job_data, error)

      expect(record).to have_attributes(
        channel_name: 'SyncStatusChannel',
        target_type: 'SyncSession',
        target_id: sync_session.id,
        data: { 'status' => 'processing' },
        priority: 'high',
        error_type: 'record_not_found',
        error_message: 'Record not found',
        retry_count: 2,
        sidekiq_job_id: 'job123'
      )
      expect(record.failed_at).to be_within(1.second).of(Time.current)
    end

    it 'handles missing job data gracefully' do
      minimal_job = {
        'args' => [ 'SyncStatusChannel', 1, 'SyncSession' ],
        'jid' => 'job456'
      }

      record = described_class.create_from_job_failure!(minimal_job, error)

      expect(record.data).to eq({})
      expect(record.priority).to eq('medium')
      expect(record.retry_count).to eq(0)
    end
  end

  describe '.classify_error', integration: true do
    it 'classifies ActiveRecord::RecordNotFound' do
      error = ActiveRecord::RecordNotFound.new
      expect(described_class.classify_error(error)).to eq('record_not_found')
    end

    it 'classifies timeout errors' do
      expect(described_class.classify_error(Timeout::Error.new)).to eq('connection_timeout')
      expect(described_class.classify_error(Net::ReadTimeout.new)).to eq('connection_timeout')
      expect(described_class.classify_error(Net::OpenTimeout.new)).to eq('connection_timeout')
    end

    it 'classifies JSON errors' do
      expect(described_class.classify_error(JSON::ParserError.new("parse error"))).to eq('serialization_error')
      expect(described_class.classify_error(JSON::GeneratorError.new("generate error"))).to eq('serialization_error')
    end

    it 'classifies validation errors' do
      record = build(:failed_broadcast_store, channel_name: nil)
      record.valid? # populate errors
      error = ActiveModel::ValidationError.new(record)
      expect(described_class.classify_error(error)).to eq('validation_error')
    end

    it 'defaults to unknown for other errors' do
      expect(described_class.classify_error(StandardError.new)).to eq('unknown')
    end
  end

  describe '.recovery_stats', integration: true do
    before do
      travel_to 2.hours.ago do
        create(:failed_broadcast_store, error_type: 'connection_timeout', priority: 'high')
        create(:failed_broadcast_store, :recovered, error_type: 'job_error', priority: 'medium')
      end

      create(:failed_broadcast_store, error_type: 'record_not_found', priority: 'low')
      create(:failed_broadcast_store, :recovered, error_type: 'connection_timeout', priority: 'critical')
    end

    it 'returns comprehensive recovery statistics' do
      stats = described_class.recovery_stats(time_period: 24.hours)

      expect(stats).to include(
        total_failures: 4,
        recovered: 2,
        pending_recovery: 2
      )

      expect(stats[:by_error_type]).to include(
        'connection_timeout' => 2,
        'job_error' => 1,
        'record_not_found' => 1
      )

      expect(stats[:by_priority]).to include(
        'high' => 1,
        'medium' => 1,
        'low' => 1,
        'critical' => 1
      )
    end

    it 'filters by time period correctly' do
      # Clear previous test data and create fresh records
      described_class.delete_all

      # Create records within the last hour by explicitly setting failed_at
      current_time = Time.current
      record1 = create(:failed_broadcast_store,
                      error_type: 'validation_error',
                      priority: 'medium',
                      failed_at: current_time)

      record2 = create(:failed_broadcast_store,
                      error_type: 'connection_timeout',
                      priority: 'high',
                      failed_at: current_time - 30.minutes)

      # Create record outside the time window (should be excluded)
      create(:failed_broadcast_store,
             error_type: 'job_error',
             priority: 'low',
             failed_at: current_time - 2.hours)

      # Query from current time
      travel_to(current_time) do
        stats = described_class.recovery_stats(time_period: 1.hour)
        expect(stats[:total_failures]).to eq(2) # Only records within the last hour
      end
    end
  end

  describe '.cleanup_old_records', integration: true do
    let!(:old_recovered) { create(:failed_broadcast_store, :recovered, recovered_at: 2.weeks.ago) }
    let!(:recent_recovered) { create(:failed_broadcast_store, :recovered, recovered_at: 2.days.ago) }
    let!(:unrecovered) { create(:failed_broadcast_store) }

    it 'deletes old recovered records' do
      expect {
        described_class.cleanup_old_records(older_than: 1.week)
      }.to change(described_class, :count).by(-1)

      expect(described_class.exists?(old_recovered.id)).to be false
      expect(described_class.exists?(recent_recovered.id)).to be true
      expect(described_class.exists?(unrecovered.id)).to be true
    end

    it 'returns count of deleted records' do
      deleted_count = described_class.cleanup_old_records(older_than: 1.week)
      expect(deleted_count).to eq(1)
    end
  end

  describe '#can_retry?', integration: true do
    it 'returns true when unrecovered and under retry limit' do
      record = create(:failed_broadcast_store, retry_count: 2, priority: 'medium')
      expect(record.can_retry?).to be true
    end

    it 'returns false when already recovered' do
      record = create(:failed_broadcast_store, :recovered, retry_count: 1)
      expect(record.can_retry?).to be false
    end

    it 'returns false when retry count equals max attempts' do
      record = create(:failed_broadcast_store, retry_count: 3, priority: 'medium')
      expect(record.can_retry?).to be false
    end

    it 'returns false when retry count exceeds max attempts' do
      record = create(:failed_broadcast_store, retry_count: 5, priority: 'medium')
      expect(record.can_retry?).to be false
    end
  end

  describe '#mark_recovered!', integration: true do
    let(:record) { create(:failed_broadcast_store) }

    it 'marks record as recovered with timestamp' do
      freeze_time do
        record.mark_recovered!(notes: 'Manual fix applied')

        expect(record.reload).to have_attributes(
          recovered_at: Time.current,
          recovery_notes: 'Manual fix applied'
        )
      end
    end

    it 'marks recovered without notes' do
      freeze_time do
        record.mark_recovered!

        expect(record.reload.recovered_at).to eq(Time.current)
        expect(record.recovery_notes).to be_nil
      end
    end
  end

  describe '#retry_broadcast!', integration: true do
    let(:record) { create(:failed_broadcast_store, target_id: sync_session.id) }

    context 'when retry succeeds' do
      before do
        allow(Services::BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)
      end

      it 'retries broadcast successfully' do
        result = record.retry_broadcast!

        expect(result).to be true
        expect(Services::BroadcastReliabilityService).to have_received(:broadcast_with_retry).with(
          channel: record.channel_name,
          target: sync_session,
          data: record.data,
          priority: record.priority.to_sym
        )
      end

      it 'increments retry count' do
        expect {
          record.retry_broadcast!
        }.to change { record.reload.retry_count }.by(1)
      end

      it 'marks as recovered with automatic retry note' do
        record.retry_broadcast!

        record.reload
        expect(record.recovered_at).to be_present
        expect(record.recovery_notes).to eq('Automatic retry successful')
      end

      it 'marks as recovered with manual retry note' do
        record.retry_broadcast!(manual: true)

        record.reload
        expect(record.recovery_notes).to eq('Manual retry successful')
      end

      it 'logs successful retry' do
        allow(Rails.logger).to receive(:info)

        record.retry_broadcast!

        expect(Rails.logger).to have_received(:info).with(
          match(/FAILED_BROADCAST.*Successfully retried.*SyncStatusChannel.*SyncSession##{sync_session.id}/)
        )
      end
    end

    context 'when retry fails' do
      before do
        allow(Services::BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(false)
      end

      it 'returns false and does not mark as recovered' do
        result = record.retry_broadcast!

        expect(result).to be false
        expect(record.reload.recovered_at).to be_nil
      end

      it 'still increments retry count' do
        expect {
          record.retry_broadcast!
        }.to change { record.reload.retry_count }.by(1)
      end

      it 'logs failed retry' do
        allow(Rails.logger).to receive(:warn)

        record.retry_broadcast!

        expect(Rails.logger).to have_received(:warn).with(
          match(/FAILED_BROADCAST.*Retry failed.*SyncStatusChannel.*SyncSession##{sync_session.id}/)
        )
      end
    end

    context 'when target no longer exists' do
      let(:record) { create(:failed_broadcast_store, :record_not_found) }

      it 'returns false and updates error' do
        result = record.retry_broadcast!

        expect(result).to be false
        record.reload
        expect(record.error_type).to eq('record_not_found')
        expect(record.error_message).to match(/Target no longer exists/)
      end
    end

    context 'when broadcast raises exception' do
      let(:error_message) { 'New connection error' }

      before do
        allow(Services::BroadcastReliabilityService).to receive(:broadcast_with_retry)
          .and_raise(StandardError, error_message)
      end

      it 'returns false and updates error information' do
        result = record.retry_broadcast!

        expect(result).to be false
        record.reload
        expect(record.error_type).to eq('unknown')
        expect(record.error_message).to eq(error_message)
      end

      it 'logs retry error' do
        allow(Rails.logger).to receive(:error)

        record.retry_broadcast!

        expect(Rails.logger).to have_received(:error).with(
          match(/FAILED_BROADCAST.*Retry error.*#{error_message}/)
        )
      end
    end

    context 'when retry count is at maximum' do
      let(:record) { create(:failed_broadcast_store, :max_retries_reached) }

      before do
        allow(Services::BroadcastReliabilityService).to receive(:broadcast_with_retry)
      end

      it 'returns false without attempting retry' do
        result = record.retry_broadcast!

        expect(result).to be false
        expect(Services::BroadcastReliabilityService).not_to have_received(:broadcast_with_retry)
      end
    end

    context 'when already recovered' do
      let(:record) { create(:failed_broadcast_store, :recovered) }

      before do
        allow(Services::BroadcastReliabilityService).to receive(:broadcast_with_retry)
      end

      it 'returns false without attempting retry' do
        result = record.retry_broadcast!

        expect(result).to be false
        expect(Services::BroadcastReliabilityService).not_to have_received(:broadcast_with_retry)
      end
    end
  end

  describe '#target_object', integration: true do
    let(:record) { create(:failed_broadcast_store, target_id: sync_session.id) }

    it 'returns target object when it exists' do
      expect(record.target_object).to eq(sync_session)
    end

    it 'returns nil when target does not exist' do
      record.target_id = 99999
      expect(record.target_object).to be_nil
    end

    it 'returns nil when target class does not exist' do
      record.target_type = 'NonExistentClass'
      expect(record.target_object).to be_nil
    end
  end

  describe '#target_exists?', integration: true do
    let(:record) { create(:failed_broadcast_store, target_id: sync_session.id) }

    it 'returns true when target exists' do
      expect(record.target_exists?).to be true
    end

    it 'returns false when target does not exist' do
      record.target_id = 99999
      expect(record.target_exists?).to be false
    end
  end

  describe '#error_description', integration: true do
    it 'returns specific description for record_not_found' do
      record = build(:failed_broadcast_store, :record_not_found)
      expect(record.error_description).to eq('Target object SyncSession#999 not found')
    end

    it 'returns specific description for connection_timeout' do
      record = build(:failed_broadcast_store, error_type: 'connection_timeout')
      expect(record.error_description).to eq('Connection timeout while broadcasting')
    end

    it 'returns specific description for serialization_error' do
      record = build(:failed_broadcast_store, error_type: 'serialization_error')
      expect(record.error_description).to eq('Failed to serialize broadcast data')
    end

    it 'returns specific description for validation_error' do
      record = build(:failed_broadcast_store, error_type: 'validation_error')
      expect(record.error_description).to eq('Validation failed during broadcast')
    end

    it 'returns truncated error message for unknown types' do
      long_message = 'A' * 200
      record = build(:failed_broadcast_store, error_type: 'unknown', error_message: long_message)
      expect(record.error_description).to eq(long_message.truncate(100))
    end
  end

  describe '#age', integration: true do
    it 'returns time since failure' do
      record = create(:failed_broadcast_store, failed_at: 2.hours.ago)
      expect(record.age).to be_within(1.second).of(2.hours)
    end
  end

  describe '#stale?', integration: true do
    it 'returns true for old recovered records' do
      record = create(:failed_broadcast_store, :recovered, failed_at: 2.weeks.ago)
      expect(record.stale?).to be true
    end

    it 'returns true for old records that have reached max retries' do
      record = create(:failed_broadcast_store, :max_retries_reached, failed_at: 2.weeks.ago)
      expect(record.stale?).to be true
    end

    it 'returns false for recent records' do
      record = create(:failed_broadcast_store, failed_at: 1.day.ago)
      expect(record.stale?).to be false
    end

    it 'returns false for old unrecovered records under retry limit' do
      record = create(:failed_broadcast_store, failed_at: 2.weeks.ago, retry_count: 1)
      expect(record.stale?).to be false
    end
  end
end
