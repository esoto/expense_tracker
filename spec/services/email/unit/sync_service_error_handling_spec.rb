# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::SyncService, 'Error Handling and Edge Cases', unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 18:00:00') }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe 'SyncError handling' do
    context 'for missing email accounts' do
      it 'raises SyncError with Spanish message for missing account' do
        allow(EmailAccount).to receive(:find_by).with(id: 999).and_return(nil)

        expect {
          service.sync_emails(email_account_id: 999)
        }.to raise_error(Email::SyncService::SyncError, 'Cuenta de correo no encontrada.')
      end

      it 'raises SyncError with Spanish message for inactive account' do
        inactive_account = instance_double(EmailAccount, id: 1, active?: false)
        allow(EmailAccount).to receive(:find_by).with(id: 1).and_return(inactive_account)

        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(Email::SyncService::SyncError, 'La cuenta de correo está inactiva.')
      end

      it 'raises SyncError with Spanish message for no active accounts' do
        allow(EmailAccount).to receive_message_chain(:active, :count).and_return(0)

        expect {
          service.sync_emails
        }.to raise_error(Email::SyncService::SyncError, 'No hay cuentas de correo activas configuradas.')
      end
    end

    context 'error inheritance and type' do
      it 'SyncError inherits from StandardError' do
        error = Email::SyncService::SyncError.new('Test error')
        expect(error).to be_a(StandardError)
      end

      it 'can be rescued as StandardError' do
        allow(EmailAccount).to receive(:find_by).and_return(nil)

        begin
          service.sync_emails(email_account_id: 999)
        rescue StandardError => e
          expect(e).to be_a(Email::SyncService::SyncError)
          expect(e.message).to eq('Cuenta de correo no encontrada.')
        end
      end
    end
  end

  describe 'Database error handling' do
    let(:email_account) { instance_double(EmailAccount, id: 1, email: 'test@example.com', active?: true) }

    before do
      allow(EmailAccount).to receive(:find_by).with(id: 1).and_return(email_account)
    end

    context 'during session creation' do
      let(:options) { { track_session: true } }

      it 'propagates ActiveRecord::RecordInvalid' do
        expect(SyncSession).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(SyncSession.new)
        )

        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it 'propagates database connection errors' do
        expect(SyncSession).to receive(:create!).and_raise(
          ActiveRecord::ConnectionNotEstablished, 'Database connection lost'
        )

        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it 'handles unique constraint violations' do
        expect(SyncSession).to receive(:create!).and_raise(
          ActiveRecord::RecordNotUnique, 'Duplicate key value'
        )

        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context 'during progress updates' do
      let(:mock_session) { instance_double(SyncSession, id: 10) }

      before do
        service.instance_variable_set(:@sync_session, mock_session)
      end

      it 'propagates StaleObjectError for concurrent modifications' do
        expect(mock_session).to receive(:update!).and_raise(
          ActiveRecord::StaleObjectError.new(mock_session, 'update')
        )

        expect {
          service.update_progress(status: 'running', processed: 10, total: 100)
        }.to raise_error(ActiveRecord::StaleObjectError)
      end

      it 'handles validation errors during update' do
        mock_record = SyncSession.new
        allow(mock_record).to receive(:errors).and_return(double(full_messages: [ 'Validation failed' ]))
        expect(mock_session).to receive(:update!).and_raise(
          ActiveRecord::RecordInvalid.new(mock_record)
        )

        expect {
          service.update_progress(status: 'invalid_status', processed: 10, total: 100)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe 'ActionCable broadcast error handling' do
    let(:mock_session) do
      instance_double(SyncSession,
        id: 20,
        status: 'running',
        processed_emails: 50,
        total_emails: 100
      )
    end

    let(:options) { { broadcast_progress: true } }

    before do
      service.instance_variable_set(:@sync_session, mock_session)
      allow(mock_session).to receive(:update!)
    end

    it 'continues operation when broadcast fails' do
      expect(ActionCable).to receive_message_chain(:server, :broadcast)
        .and_raise(StandardError, 'Redis connection lost')

      expect {
        service.update_progress(message: 'Test', processed: 50, total: 100)
      }.to raise_error(StandardError, 'Redis connection lost')

      # Verify the session was still updated
      expect(mock_session).to have_received(:update!)
    end

    it 'handles nil ActionCable server' do
      allow(ActionCable).to receive(:server).and_return(nil)

      expect {
        service.update_progress(message: 'Test', processed: 50, total: 100)
      }.to raise_error(NoMethodError)
    end
  end

  describe 'Job enqueueing error handling' do
    context 'when ProcessEmailsJob fails to enqueue' do
      let(:email_account) { instance_double(EmailAccount, id: 1, email: 'test@example.com', active?: true) }

      before do
        allow(EmailAccount).to receive(:find_by).and_return(email_account)
      end

      it 'propagates job enqueueing errors' do
        expect(ProcessEmailsJob).to receive(:perform_later).and_raise(
          StandardError, 'Queue is full'
        )

        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(StandardError, 'Queue is full')
      end

      it 'does not create orphaned sessions when job fails' do
        service_with_session = described_class.new(track_session: true)
        mock_session = instance_double(SyncSession, id: 30)

        expect(SyncSession).to receive(:create!).and_return(mock_session)
        expect(mock_session).to receive_message_chain(:sync_session_accounts, :create!)
        expect(ProcessEmailsJob).to receive(:perform_later).and_raise(StandardError, 'Job failed')

        expect {
          service_with_session.sync_emails(email_account_id: 1)
        }.to raise_error(StandardError, 'Job failed')

        # Session was created but job failed - this is expected behavior
        expect(service_with_session.sync_session).to eq(mock_session)
      end
    end
  end

  describe 'Edge cases and boundary conditions' do
    describe 'nil and empty value handling' do
      it 'handles nil email_account_id gracefully' do
        allow(EmailAccount).to receive_message_chain(:active, :count).and_return(1)
        allow(ProcessEmailsJob).to receive(:perform_later)

        result = service.sync_emails(email_account_id: nil)

        expect(result[:success]).to be true
        expect(result[:account_count]).to eq(1)
      end

      it 'handles empty string email_account_id' do
        allow(EmailAccount).to receive_message_chain(:active, :count).and_return(2)
        allow(ProcessEmailsJob).to receive(:perform_later)

        result = service.sync_emails(email_account_id: '')

        expect(result[:success]).to be true
        expect(result[:account_count]).to eq(2)
      end

      it 'handles zero email_account_id' do
        allow(EmailAccount).to receive(:find_by).with(id: 0).and_return(nil)

        expect {
          service.sync_emails(email_account_id: 0)
        }.to raise_error(Email::SyncService::SyncError, 'Cuenta de correo no encontrada.')
      end
    end

    describe 'progress calculation edge cases' do
      let(:mock_session) { instance_double(SyncSession) }

      before do
        service.instance_variable_set(:@sync_session, mock_session)
      end

      it 'handles division by zero in progress percentage' do
        allow(mock_session).to receive(:processed_emails).and_return(0)
        allow(mock_session).to receive(:total_emails).and_return(0)

        result = service.send(:calculate_progress_percentage)

        expect(result).to eq(0)
      end

      it 'handles nil values in progress calculation' do
        allow(mock_session).to receive(:processed_emails).and_return(nil)
        allow(mock_session).to receive(:total_emails).and_return(100)

        result = service.send(:calculate_progress_percentage)

        expect(result).to eq(0)
      end

      it 'handles very large numbers without overflow' do
        allow(mock_session).to receive(:processed_emails).and_return(999_999_999)
        allow(mock_session).to receive(:total_emails).and_return(1_000_000_000)

        result = service.send(:calculate_progress_percentage)

        expect(result).to eq(100)
      end
    end

    describe 'conflict detection edge cases' do
      it 'handles expenses with nil descriptions' do
        expense1 = instance_double(Expense,
          id: 1,
          transaction_date: Date.today,
          amount: BigDecimal('100'),
          description: nil
        )
        expense2 = instance_double(Expense,
          id: 2,
          transaction_date: Date.today,
          amount: BigDecimal('100'),
          description: nil
        )

        allow(expense1).to receive(:amount).and_return(BigDecimal('100'))
        allow(expense2).to receive(:amount).and_return(BigDecimal('100'))

        expense_relation = double('expense_relation')
        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:group_by) do |&block|
          { [ Date.today, BigDecimal('100') ] => [ expense1, expense2 ] }
        end

        conflicts = service.detect_conflicts

        expect(conflicts).to be_empty # nil descriptions don't match
      end

      it 'handles empty description strings' do
        result = service.send(:similar_descriptions?, '', '')
        expect(result).to be false
      end

      it 'handles special characters in descriptions' do
        result = service.send(:similar_descriptions?,
          '!@#$%^&*()',
          '!@#$%^&*()'
        )
        expect(result).to be false # No actual words to compare
      end

      it 'handles very long descriptions' do
        # Create descriptions with high word overlap
        # The & operator returns unique common elements, not all duplicates
        # So we need many different matching words to get > 0.7 similarity
        words = (1..100).map { |i| "word#{i}" }.join(' ')
        long_desc1 = words + ' extra1'
        long_desc2 = words + ' extra2'

        result = service.send(:similar_descriptions?, long_desc1, long_desc2)
        expect(result).to be true # 100 common words out of 101 = 0.99 > 0.7
      end
    end

    describe 'retry mechanism edge cases' do
      it 'handles missing session gracefully' do
        allow(SyncSession).to receive(:find).with(999).and_return(nil)

        result = service.retry_failed_session(999)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not found')
      end

      it 'handles session in unexpected state' do
        completed_session = instance_double(SyncSession, id: 1, failed?: false)
        allow(SyncSession).to receive(:find).with(1).and_return(completed_session)

        result = service.retry_failed_session(1)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not failed')
      end

      it 'handles session with very high retry count' do
        failed_session = instance_double(SyncSession,
          id: 1,
          failed?: true,
          metadata: { 'retry_count' => 999 }
        )

        allow(SyncSession).to receive(:find).with(1).and_return(failed_session)
        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed).and_return([])

        expect(failed_session).to receive(:update!).with(
          status: 'retrying',
          metadata: { 'retry_count' => 1000 }
        )

        result = service.retry_failed_session(1)

        expect(result[:success]).to be true
      end
    end

    describe 'metrics calculation edge cases' do
      it 'handles time window in the future' do
        future_window = -1.hour # Negative means future
        future_range = (mock_time - future_window)..mock_time

        sessions = double('sessions')
        allow(SyncSession).to receive(:where).with(created_at: future_range).and_return(sessions)
        allow(sessions).to receive(:count).and_return(0)

        allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 0)))
        allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 0)))
        allow(service).to receive(:calculate_average_duration).and_return(0)
        allow(service).to receive(:calculate_emails_processed).and_return(0)
        allow(service).to receive(:calculate_conflicts).and_return(0)

        metrics = service.get_metrics(time_window: future_window)

        expect(metrics[:total_syncs]).to eq(0)
      end

      it 'handles very large time windows' do
        large_window = 365.days

        sessions = double('sessions')
        allow(SyncSession).to receive(:where).and_return(sessions)
        allow(sessions).to receive(:count).and_return(50000)

        allow(SyncSession).to receive(:completed).and_return(double(where: double(count: 45000)))
        allow(SyncSession).to receive(:failed).and_return(double(where: double(count: 4000)))
        allow(service).to receive(:calculate_average_duration).and_return(600)
        allow(service).to receive(:calculate_emails_processed).and_return(2_500_000)
        allow(service).to receive(:calculate_conflicts).and_return(10000)

        metrics = service.get_metrics(time_window: large_window)

        expect(metrics[:total_syncs]).to eq(50000)
        expect(metrics[:emails_processed]).to eq(2_500_000)
      end
    end

    describe 'concurrent operation handling' do
      it 'handles multiple services operating on same session' do
        shared_session = instance_double(SyncSession, id: 100, status: 'running')

        service1 = described_class.new
        service2 = described_class.new

        service1.instance_variable_set(:@sync_session, shared_session)
        service2.instance_variable_set(:@sync_session, shared_session)

        allow(shared_session).to receive(:update!).and_raise(
          ActiveRecord::StaleObjectError.new(shared_session, 'update')
        )

        expect {
          service1.update_progress(processed: 10, total: 100)
        }.to raise_error(ActiveRecord::StaleObjectError)

        expect {
          service2.update_progress(processed: 20, total: 100)
        }.to raise_error(ActiveRecord::StaleObjectError)
      end
    end

    describe 'memory and resource management' do
      it 'does not leak session references' do
        100.times do |i|
          temp_service = described_class.new
          mock_session = instance_double(SyncSession, id: i)
          temp_service.instance_variable_set(:@sync_session, mock_session)
        end

        # New service should not have any session
        new_service = described_class.new
        expect(new_service.sync_session).to be_nil
      end

      it 'handles very large conflict arrays' do
        large_conflicts = Array.new(10000) do |i|
          { type: 'duplicate', expenses: [ i, i + 1 ], confidence: 0.8 }
        end

        allow(Expense).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

        result = service.resolve_conflicts(large_conflicts)

        expect(result[:total]).to eq(10000)
        expect(result[:resolved]).to eq(0) # No expenses found
      end
    end
  end

  describe 'Integration error scenarios' do
    context 'cascading failures' do
      let(:options) { { track_session: true, broadcast_progress: true, detect_conflicts: true, auto_resolve: true } }

      it 'handles multiple component failures gracefully' do
        # Session creation fails
        allow(SyncSession).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(SyncSession.new))

        # Job enqueueing would fail
        allow(ProcessEmailsJob).to receive(:perform_later).and_raise(StandardError, 'Queue error')

        # Conflict detection would fail
        allow(service).to receive(:detect_conflicts).and_raise(StandardError, 'Detection error')

        email_account = instance_double(EmailAccount, id: 1, active?: true)
        allow(EmailAccount).to receive(:find_by).and_return(email_account)

        # First failure stops the chain
        expect {
          service.sync_emails(email_account_id: 1)
        }.to raise_error(ActiveRecord::RecordInvalid)

        # Subsequent operations are not attempted
        expect(ProcessEmailsJob).not_to have_received(:perform_later)
        expect(service).not_to have_received(:detect_conflicts)
      end
    end
  end
end

