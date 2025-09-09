# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::SyncService, 'Metrics and Progress Tracking', unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 10:00:00') }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe '#get_metrics' do
    let(:time_window) { 1.hour }
    let(:time_range) { (mock_time - time_window)..mock_time }

    describe 'basic metrics calculation' do
      before do
        # Mock base queries
        @all_sessions = double('all_sessions')
        @completed_sessions = double('completed_sessions')
        @failed_sessions = double('failed_sessions')

        allow(SyncSession).to receive(:where).with(created_at: time_range).and_return(@all_sessions)
        allow(@all_sessions).to receive(:count).and_return(15)

        allow(SyncSession).to receive(:completed).and_return(@completed_sessions)
        allow(@completed_sessions).to receive(:where).with(created_at: time_range).and_return(@completed_sessions)
        allow(@completed_sessions).to receive(:count).and_return(12)

        allow(SyncSession).to receive(:failed).and_return(@failed_sessions)
        allow(@failed_sessions).to receive(:where).with(created_at: time_range).and_return(@failed_sessions)
        allow(@failed_sessions).to receive(:count).and_return(2)
      end

      it 'returns total sync count' do
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics

        expect(metrics[:total_syncs]).to eq(15)
      end

      it 'returns successful sync count' do
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics

        expect(metrics[:successful_syncs]).to eq(12)
      end

      it 'returns failed sync count' do
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics

        expect(metrics[:failed_syncs]).to eq(2)
      end

      it 'includes calculated metrics' do
        allow(service).to receive(:calculate_average_duration).with(time_window).and_return(45.5)
        allow(service).to receive(:calculate_emails_processed).with(time_window).and_return(500)
        allow(service).to receive(:calculate_conflicts).with(time_window).and_return(8)

        metrics = service.get_metrics

        expect(metrics).to include(
          average_duration: 45.5,
          emails_processed: 500,
          conflicts_detected: 8
        )
      end
    end

    describe 'custom time windows' do
      it 'accepts different time window periods' do
        custom_window = 24.hours
        custom_range = (mock_time - custom_window)..mock_time

        sessions = double('sessions')
        allow(SyncSession).to receive(:where).with(created_at: custom_range).and_return(sessions)
        allow(sessions).to receive(:count).and_return(100)

        allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 0)))
        allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 0)))
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics(time_window: custom_window)

        expect(metrics[:total_syncs]).to eq(100)
      end

      it 'handles zero time window edge case' do
        zero_window = 0.seconds
        zero_range = mock_time..mock_time

        sessions = double('sessions')
        allow(SyncSession).to receive(:where).with(created_at: zero_range).and_return(sessions)
        allow(sessions).to receive(:count).and_return(0)

        allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 0)))
        allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 0)))
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics(time_window: zero_window)

        expect(metrics[:total_syncs]).to eq(0)
      end
    end
  end

  describe '#calculate_average_duration (private)' do
    let(:time_window) { 2.hours }

    it 'calculates average duration for completed sessions' do
      session1 = instance_double(SyncSession,
        started_at: mock_time - 30.minutes,
        completed_at: mock_time - 25.minutes
      )
      session2 = instance_double(SyncSession,
        started_at: mock_time - 20.minutes,
        completed_at: mock_time - 10.minutes
      )

      completed_sessions = double('completed_sessions')
      allow(SyncSession).to receive(:completed).and_return(completed_sessions)
      allow(completed_sessions).to receive(:where).and_return([ session1, session2 ])

      # 5 minutes + 10 minutes = 15 minutes total, average = 7.5 minutes = 450 seconds
      result = service.send(:calculate_average_duration, time_window)

      expect(result).to eq(450.0)
    end

    it 'returns 0 for no completed sessions' do
      allow(SyncSession).to receive(:completed).and_return(double(where: []))

      result = service.send(:calculate_average_duration, time_window)

      expect(result).to eq(0)
    end

    it 'excludes sessions without completed_at' do
      session1 = instance_double(SyncSession,
        started_at: mock_time - 30.minutes,
        completed_at: nil
      )
      session2 = instance_double(SyncSession,
        started_at: mock_time - 20.minutes,
        completed_at: mock_time - 15.minutes
      )

      allow(SyncSession).to receive_message_chain(:completed, :where).and_return([ session1, session2 ])

      # Only session2: 5 minutes = 300 seconds
      result = service.send(:calculate_average_duration, time_window)

      expect(result).to eq(300.0)
    end

    it 'excludes sessions without started_at' do
      session1 = instance_double(SyncSession,
        started_at: nil,
        completed_at: mock_time - 10.minutes
      )
      session2 = instance_double(SyncSession,
        started_at: mock_time - 15.minutes,
        completed_at: mock_time - 10.minutes
      )

      allow(SyncSession).to receive_message_chain(:completed, :where).and_return([ session1, session2 ])

      # Only session2: 5 minutes = 300 seconds
      result = service.send(:calculate_average_duration, time_window)

      expect(result).to eq(300.0)
    end

    it 'returns 0 when all durations are invalid' do
      session1 = instance_double(SyncSession, started_at: nil, completed_at: nil)
      session2 = instance_double(SyncSession, started_at: nil, completed_at: mock_time)

      allow(SyncSession).to receive_message_chain(:completed, :where).and_return([ session1, session2 ])

      result = service.send(:calculate_average_duration, time_window)

      expect(result).to eq(0)
    end
  end

  describe '#calculate_emails_processed (private)' do
    let(:time_window) { 3.hours }

    it 'sums processed_emails from all sessions' do
      sessions = double('sessions')
      allow(SyncSession).to receive(:where).and_return(sessions)
      allow(sessions).to receive(:sum).with(:processed_emails).and_return(1250)

      result = service.send(:calculate_emails_processed, time_window)

      expect(result).to eq(1250)
    end

    it 'returns 0 when no sessions exist' do
      sessions = double('sessions')
      allow(SyncSession).to receive(:where).and_return(sessions)
      allow(sessions).to receive(:sum).with(:processed_emails).and_return(0)

      result = service.send(:calculate_emails_processed, time_window)

      expect(result).to eq(0)
    end

    it 'handles nil values in sum' do
      sessions = double('sessions')
      allow(SyncSession).to receive(:where).and_return(sessions)
      allow(sessions).to receive(:sum).with(:processed_emails).and_return(nil)

      result = service.send(:calculate_emails_processed, time_window)

      expect(result).to be_nil
    end
  end

  describe '#calculate_conflicts (private)' do
    let(:time_window) { 4.hours }

    it 'sums conflicts_detected from all sessions' do
      sessions = double('sessions')
      allow(SyncSession).to receive(:where).and_return(sessions)
      allow(sessions).to receive(:sum).with(:conflicts_detected).and_return(25)

      result = service.send(:calculate_conflicts, time_window)

      expect(result).to eq(25)
    end

    it 'returns 0 when no conflicts detected' do
      sessions = double('sessions')
      allow(SyncSession).to receive(:where).and_return(sessions)
      allow(sessions).to receive(:sum).with(:conflicts_detected).and_return(0)

      result = service.send(:calculate_conflicts, time_window)

      expect(result).to eq(0)
    end
  end

  describe '#broadcast_progress (private)' do
    let(:mock_session) do
      instance_double(SyncSession,
        id: 100,
        status: 'running',
        processed_emails: 50,
        total_emails: 200
      )
    end

    before do
      service.instance_variable_set(:@sync_session, mock_session)
    end

    it 'broadcasts to correct channel' do
      expect(ActionCable).to receive_message_chain(:server, :broadcast).with(
        'sync_progress_100',
        anything
      )

      service.send(:broadcast_progress, 'Processing...')
    end

    it 'includes all required fields in broadcast' do
      expect(ActionCable).to receive_message_chain(:server, :broadcast).with(
        'sync_progress_100',
        {
          session_id: 100,
          status: 'running',
          message: 'Processing batch 2 of 10',
          progress: 25
        }
      )

      service.send(:broadcast_progress, 'Processing batch 2 of 10')
    end

    it 'calculates progress percentage correctly' do
      allow(mock_session).to receive(:processed_emails).and_return(75)
      allow(mock_session).to receive(:total_emails).and_return(150)

      expect(ActionCable).to receive_message_chain(:server, :broadcast).with(
        'sync_progress_100',
        hash_including(progress: 50)
      )

      service.send(:broadcast_progress, 'Halfway done')
    end

    it 'does nothing when sync_session is nil' do
      service.instance_variable_set(:@sync_session, nil)

      expect(ActionCable).not_to receive(:server)

      service.send(:broadcast_progress, 'Test message')
    end

    it 'handles broadcast errors gracefully' do
      expect(ActionCable).to receive_message_chain(:server, :broadcast)
        .and_raise(StandardError, 'Connection lost')

      expect {
        service.send(:broadcast_progress, 'Test')
      }.to raise_error(StandardError, 'Connection lost')
    end
  end

  describe '#calculate_progress_percentage (private)' do
    let(:mock_session) { instance_double(SyncSession) }

    before do
      service.instance_variable_set(:@sync_session, mock_session)
    end

    it 'calculates percentage correctly' do
      allow(mock_session).to receive(:processed_emails).and_return(25)
      allow(mock_session).to receive(:total_emails).and_return(100)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(25)
    end

    it 'rounds to nearest integer' do
      allow(mock_session).to receive(:processed_emails).and_return(33)
      allow(mock_session).to receive(:total_emails).and_return(100)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(33)

      allow(mock_session).to receive(:processed_emails).and_return(67)
      allow(mock_session).to receive(:total_emails).and_return(200)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(34) # 33.5 rounds to 34
    end

    it 'returns 0 when total_emails is 0' do
      allow(mock_session).to receive(:processed_emails).and_return(0)
      allow(mock_session).to receive(:total_emails).and_return(0)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(0)
    end

    it 'returns 0 when total_emails is nil' do
      allow(mock_session).to receive(:processed_emails).and_return(10)
      allow(mock_session).to receive(:total_emails).and_return(nil)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(0)
    end

    it 'returns 0 when sync_session is nil' do
      service.instance_variable_set(:@sync_session, nil)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(0)
    end

    it 'handles edge case of processed > total' do
      allow(mock_session).to receive(:processed_emails).and_return(110)
      allow(mock_session).to receive(:total_emails).and_return(100)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(110) # Doesn't cap at 100
    end

    it 'handles negative values' do
      allow(mock_session).to receive(:processed_emails).and_return(-10)
      allow(mock_session).to receive(:total_emails).and_return(100)

      result = service.send(:calculate_progress_percentage)

      expect(result).to eq(-10)
    end
  end

  describe 'progress tracking integration' do
    let(:options) { { track_session: true, broadcast_progress: true } }
    let(:mock_session) do
      instance_double(SyncSession,
        id: 500,
        status: 'pending'
      )
    end

    it 'tracks progress through complete sync lifecycle' do
      email_account = instance_double(EmailAccount, id: 1, email: 'test@example.com', active?: true)

      # Setup
      allow(EmailAccount).to receive(:find_by).and_return(email_account)
      allow(ProcessEmailsJob).to receive(:perform_later)

      # Session creation
      expect(SyncSession).to receive(:create!).and_return(mock_session)
      expect(mock_session).to receive_message_chain(:sync_session_accounts, :create!)

      # Progress updates
      allow(mock_session).to receive(:update!)
      allow(mock_session).to receive(:processed_emails).and_return(0, 25, 50, 100)
      allow(mock_session).to receive(:total_emails).and_return(100)

      # Broadcast expectations
      allow(ActionCable).to receive_message_chain(:server, :broadcast)

      # Execute sync
      result = service.sync_emails(email_account_id: 1)
      expect(result[:success]).to be true

      # Simulate progress updates
      service.update_progress(status: 'running', processed: 25, total: 100, message: 'Starting...')
      service.update_progress(processed: 50, total: 100, message: 'Halfway...')
      service.update_progress(status: 'completed', processed: 100, total: 100, message: 'Done!')
    end
  end

  describe 'metrics aggregation patterns' do
    it 'provides hourly metrics by default' do
      allow(SyncSession).to receive(:where).and_return(double(count: 10))
      allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 8)))
      allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 1)))
      allow(service).to receive(:calculate_average_duration).and_return(300)
      allow(service).to receive(:calculate_emails_processed).and_return(500)
      allow(service).to receive(:calculate_conflicts).and_return(5)

      metrics = service.get_metrics # Default 1.hour

      expect(metrics).to include(
        total_syncs: 10,
        successful_syncs: 8,
        failed_syncs: 1
      )
    end

    it 'supports daily metrics aggregation' do
      allow(SyncSession).to receive(:where).and_return(double(count: 240))
      allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 220)))
      allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 15)))
      allow(service).to receive(:calculate_average_duration).and_return(450)
      allow(service).to receive(:calculate_emails_processed).and_return(12000)
      allow(service).to receive(:calculate_conflicts).and_return(120)

      metrics = service.get_metrics(time_window: 24.hours)

      expect(metrics[:total_syncs]).to eq(240)
      expect(metrics[:emails_processed]).to eq(12000)
    end
  end
end
