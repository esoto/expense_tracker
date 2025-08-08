require 'rails_helper'

RSpec.describe SyncStatusChannel, type: :channel do
  let(:sync_session) { create(:sync_session, :running) }
  let(:email_account) { create(:email_account) }
  let!(:sync_account) do
    create(:sync_session_account,
           sync_session: sync_session,
           email_account: email_account,
           status: 'processing',
           processed_emails: 25,
           total_emails: 100,
           detected_expenses: 5)
  end

  before do
    # Clear any existing broadcasts
    clear_broadcasts
  end

  describe '#subscribed' do
    context 'with valid session_id' do
      it 'successfully subscribes and receives initial status' do
        subscribe(session_id: sync_session.id)

        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_for(sync_session)
      end

      it 'transmits initial status data on subscription' do
        subscribe(session_id: sync_session.id)

        expect(transmissions.last).to include(
          "type" => "initial_status",
          "status" => "running",
          "progress_percentage" => sync_session.progress_percentage,
          "processed_emails" => sync_session.processed_emails,
          "total_emails" => sync_session.total_emails,
          "detected_expenses" => sync_session.detected_expenses
        )

        expect(transmissions.last["accounts"]).to be_an(Array)
        expect(transmissions.last["accounts"].first).to include(
          "email" => email_account.email,
          "bank" => email_account.bank_name,
          "status" => "processing"
        )
      end
    end

    context 'with invalid session_id' do
      it 'rejects subscription for non-existent session' do
        subscribe(session_id: 99999)
        expect(subscription).to be_rejected
      end

      it 'rejects subscription without session_id' do
        subscribe
        expect(subscription).to be_rejected
      end

      it 'rejects subscription with nil session_id' do
        subscribe(session_id: nil)
        expect(subscription).to be_rejected
      end
    end
  end

  describe '#unsubscribed' do
    it 'stops all streams when unsubscribing' do
      subscribe(session_id: sync_session.id)
      expect(subscription).to have_stream_for(sync_session)

      unsubscribe
      expect(subscription).not_to have_streams
    end
  end

  describe 'class methods for broadcasting' do
    before do
      # Subscribe to the channel to receive broadcasts
      subscribe(session_id: sync_session.id)
    end

    describe '.broadcast_progress' do
      it 'broadcasts progress update with correct data' do
        expect {
          SyncStatusChannel.broadcast_progress(sync_session, 50, 100, 10)
        }.to have_broadcasted_to(sync_session).with(
          hash_including(
            "type" => "progress_update",
            "status" => sync_session.status,
            "progress_percentage" => sync_session.progress_percentage,
            "processed_emails" => 50,
            "total_emails" => 100,
            "detected_expenses" => 10
          )
        )
      end

      it 'handles nil detected expenses gracefully' do
        expect {
          SyncStatusChannel.broadcast_progress(sync_session, 30, 100, nil)
        }.to have_broadcasted_to(sync_session).with(
          hash_including(
            "type" => "progress_update",
            "detected_expenses" => sync_session.detected_expenses
          )
        )
      end

      it 'does not broadcast with nil session' do
        expect {
          SyncStatusChannel.broadcast_progress(nil, 50, 100, 10)
        }.not_to have_broadcasted_to(sync_session)
      end
    end

    describe '.broadcast_account_progress' do
      it 'broadcasts account-specific progress update' do
        sync_account.update!(processed_emails: 75, detected_expenses: 8)

        expect {
          SyncStatusChannel.broadcast_account_progress(sync_session, sync_account)
        }.to have_broadcasted_to(sync_session).with(
          type: "account_update",
          account_id: email_account.id,
          sync_account_id: sync_account.id,
          status: 'processing',
          progress: 75,
          processed: 75,
          total: 100,
          detected: 8
        )
      end
    end

    describe '.broadcast_completion' do
      let(:completed_session) { create(:sync_session, :completed) }

      before do
        subscribe(session_id: completed_session.id)
      end

      it 'broadcasts completion with final stats' do
        expect {
          SyncStatusChannel.broadcast_completion(completed_session)
        }.to have_broadcasted_to(completed_session).with(
          hash_including(
            "type" => "completed",
            "status" => "completed",
            "progress_percentage" => 100,
            "message" => "Sincronización completada exitosamente"
          )
        )
      end

      it 'includes duration in completion broadcast' do
        completed_session.update!(
          started_at: 5.minutes.ago,
          completed_at: Time.current
        )

        expect {
          SyncStatusChannel.broadcast_completion(completed_session)
        }.to have_broadcasted_to(completed_session).with(
          hash_including(duration: match(/\d+m\s\d+s/))
        )
      end
    end

    describe '.broadcast_failure' do
      let(:failed_session) { create(:sync_session, :failed) }

      before do
        subscribe(session_id: failed_session.id)
      end

      it 'broadcasts failure with error message' do
        error_message = "IMAP connection timeout"

        expect {
          SyncStatusChannel.broadcast_failure(failed_session, error_message)
        }.to have_broadcasted_to(failed_session).with(
          hash_including(
            "type" => "failed",
            "status" => "failed",
            "error" => error_message
          )
        )
      end

      it 'uses session error_details when no message provided' do
        expect {
          SyncStatusChannel.broadcast_failure(failed_session)
        }.to have_broadcasted_to(failed_session).with(
          hash_including(
            "type" => "failed",
            "error" => failed_session.error_details
          )
        )
      end

      it 'provides default error message when none available' do
        failed_session.update!(error_details: nil)

        expect {
          SyncStatusChannel.broadcast_failure(failed_session, nil)
        }.to have_broadcasted_to(failed_session).with(
          hash_including(
            "type" => "failed",
            "error" => "Error durante la sincronización"
          )
        )
      end
    end

    describe '.broadcast_status' do
      it 'broadcasts complete status update with accounts data' do
        expect {
          SyncStatusChannel.broadcast_status(sync_session)
        }.to have_broadcasted_to(sync_session).with(
          hash_including(
            "type" => "status_update",
            "status" => sync_session.status,
            "progress_percentage" => sync_session.progress_percentage
          )
        )
      end

      it 'reloads session data before broadcasting' do
        # Update session in database
        sync_session.update_column(:processed_emails, 80)

        expect {
          SyncStatusChannel.broadcast_status(sync_session)
        }.to have_broadcasted_to(sync_session).with(
          hash_including(processed_emails: 80)
        )
      end
    end

    describe '.broadcast_activity' do
      it 'broadcasts activity message with timestamp' do
        freeze_time do
          expect {
            SyncStatusChannel.broadcast_activity(sync_session, "email_processed", "Processing BAC email")
          }.to have_broadcasted_to(sync_session).with(
            type: "activity",
            activity_type: "email_processed",
            message: "Processing BAC email",
            timestamp: Time.current.iso8601
          )
        end
      end
    end
  end

  describe 'error handling' do
    it 'handles database errors gracefully during subscription' do
      allow(SyncSession).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid)

      expect {
        subscribe(session_id: sync_session.id)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'handles broadcasting errors gracefully' do
      subscribe(session_id: sync_session.id)

      # Mock a broadcasting error
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError)

      expect {
        SyncStatusChannel.broadcast_progress(sync_session, 50, 100, 10)
      }.to raise_error(StandardError)
    end
  end

  describe 'concurrent subscriptions' do
    let(:another_session) { create(:sync_session, :running) }

    it 'handles multiple subscriptions to different sessions' do
      # Subscribe to first session
      connection1 = subscribe(session_id: sync_session.id)
      expect(connection1).to be_confirmed

      # Subscribe to second session from same connection (simulate new tab)
      connection2 = subscribe(session_id: another_session.id)
      expect(connection2).to be_confirmed

      # Both should receive their respective broadcasts
      expect {
        SyncStatusChannel.broadcast_progress(sync_session, 25, 100, 5)
      }.to have_broadcasted_to(sync_session)

      expect {
        SyncStatusChannel.broadcast_progress(another_session, 75, 200, 15)
      }.to have_broadcasted_to(another_session)
    end
  end

  describe 'performance' do
    it 'handles rapid successive broadcasts efficiently' do
      subscribe(session_id: sync_session.id)

      # Simulate rapid progress updates
      # Simulate rapid progress updates
      10.times do |i|
        SyncStatusChannel.broadcast_progress(sync_session, i * 10, 100, i)
      end

      # Check that all broadcasts were sent
      expect(ActionCable.server.pubsub.broadcasts("sync_status:#{sync_session.to_gid_param}").size).to eq(10)
    end

    it 'limits account data size in broadcasts' do
      # Create many sync session accounts
      25.times do
        create(:sync_session_account, sync_session: sync_session, email_account: create(:email_account))
      end

      expect {
        SyncStatusChannel.broadcast_status(sync_session)
      }.to have_broadcasted_to(sync_session)

      # Check that broadcast completes quickly even with many accounts
      broadcasts = ActionCable.server.pubsub.broadcasts("sync_status:#{sync_session.to_gid_param}")
      expect(broadcasts).not_to be_empty
    end
  end
end
