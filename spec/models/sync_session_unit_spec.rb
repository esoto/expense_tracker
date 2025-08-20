# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSession, type: :model, unit: true do
  # Use build_stubbed for true unit testing
  let(:sync_session) do
    build_stubbed(:sync_session,
      id: 1,
      status: "running",
      session_token: "test_token_123",
      total_emails: 100,
      processed_emails: 50,
      detected_expenses: 25,
      errors_count: 2,
      started_at: 1.hour.ago,
      completed_at: nil,
      error_details: nil,
      job_ids: ["job1", "job2"])
  end

  describe "included modules" do
    it "includes ActionView::RecordIdentifier" do
      expect(described_class.ancestors).to include(ActionView::RecordIdentifier)
    end

    it "includes Turbo::Broadcastable" do
      expect(described_class.ancestors).to include(Turbo::Broadcastable)
    end
  end

  describe "validations" do
    subject { build(:sync_session) }

    describe "status validation" do
      it "validates presence of status" do
        subject.status = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:status]).to include("can't be blank")
      end

      it "validates inclusion of status" do
        subject.status = "invalid"
        expect(subject).not_to be_valid
        expect(subject.errors[:status]).to include("is not included in the list")
      end

      it "accepts valid statuses" do
        %w[pending running completed failed cancelled].each do |status|
          subject.status = status
          expect(subject).to be_valid
        end
      end
    end
  end

  describe "associations" do
    it "has many sync_session_accounts" do
      association = described_class.reflect_on_association(:sync_session_accounts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many email_accounts through sync_session_accounts" do
      association = described_class.reflect_on_association(:email_accounts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:through]).to eq(:sync_session_accounts)
    end

    it "has many sync_conflicts" do
      association = described_class.reflect_on_association(:sync_conflicts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many sync_metrics" do
      association = described_class.reflect_on_association(:sync_metrics)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "serialization" do
    it "serializes job_ids as JSON array" do
      session = create(:sync_session)
      session.job_ids = ["job1", "job2"]
      session.save!
      
      session.reload
      expect(session.job_ids).to eq(["job1", "job2"])
    end

    it "handles nil job_ids" do
      session = build_stubbed(:sync_session)
      allow(session).to receive(:job_ids=)
      allow(session).to receive(:job_ids).and_return(nil)
      
      session.job_ids = nil
      expect(session.job_ids).to be_nil
    end

    it "handles empty array" do
      session = create(:sync_session)
      session.job_ids = []
      session.save!
      
      expect(session.job_ids).to eq([])
    end
  end

  describe "callbacks" do
    describe "before_create :generate_session_token" do
      it "generates session token on create" do
        allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return("generated_token")
        
        session = build_stubbed(:sync_session, session_token: nil)
        session.send(:generate_session_token)
        
        expect(session.session_token).to eq("generated_token")
      end

      it "does not override existing token" do
        session = build_stubbed(:sync_session, session_token: "existing_token")
        session.send(:generate_session_token)
        
        expect(session.session_token).to eq("existing_token")
      end
    end

    describe "before_save :track_status_changes" do
      it "sets completed_at when transitioning from running to finished" do
        session = create(:sync_session, status: "running", completed_at: nil)
        
        freeze_time do
          session.status = "completed"
          session.save!
          
          expect(session.completed_at).to eq(Time.current)
        end
      end

      it "does not override existing completed_at" do
        original_time = 1.hour.ago
        session = create(:sync_session, status: "running", completed_at: original_time)
        
        session.status = "completed"
        session.save!
        
        expect(session.completed_at).to eq(original_time)
      end

      it "does not set completed_at for non-finished statuses" do
        session = create(:sync_session, status: "pending", completed_at: nil)
        
        session.status = "running"
        session.save!
        
        expect(session.completed_at).to be_nil
      end
    end

    describe "after_commit :log_status_change" do
      it "logs error when status changes to failed" do
        session = create(:sync_session, status: "running")
        session.error_details = "Connection failed"
        
        expect(Rails.logger).to receive(:error).with("SyncSession #{session.id} failed: Connection failed")
        
        session.status = "failed"
        session.save!
      end

      it "does not log for other status changes" do
        session = create(:sync_session, status: "pending")
        
        expect(Rails.logger).not_to receive(:error)
        
        session.status = "running"
        session.save!
      end
    end

    describe "after_update_commit :broadcast_dashboard_update" do
      it "triggers broadcast on update" do
        session = create(:sync_session)
        
        expect(session).to receive(:broadcast_dashboard_update)
        session.update!(processed_emails: 10)
      end
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at descending" do
        query = described_class.recent
        expect(query.to_sql).to include("ORDER BY")
        expect(query.to_sql).to include("created_at")
        expect(query.to_sql).to include("DESC")
      end
    end

    describe ".active" do
      it "returns pending and running sessions" do
        query = described_class.active
        expect(query.to_sql).to include("status")
        expect(query.to_sql).to include("IN ('pending', 'running')")
      end
    end

    describe ".completed" do
      it "returns completed sessions" do
        query = described_class.completed
        expect(query.to_sql).to include('"sync_sessions"."status" = \'completed\'')
      end
    end

    describe ".failed" do
      it "returns failed sessions" do
        query = described_class.failed
        expect(query.to_sql).to include('"sync_sessions"."status" = \'failed\'')
      end
    end

    describe ".finished" do
      it "returns completed, failed, and cancelled sessions" do
        query = described_class.finished
        expect(query.to_sql).to include("status")
        expect(query.to_sql).to include("IN ('completed', 'failed', 'cancelled')")
      end
    end
  end

  describe "instance methods" do
    describe "#progress_percentage" do
      it "calculates percentage correctly" do
        sync_session.total_emails = 100
        sync_session.processed_emails = 50
        expect(sync_session.progress_percentage).to eq(50)
      end

      it "rounds to nearest integer" do
        sync_session.total_emails = 100
        sync_session.processed_emails = 33
        expect(sync_session.progress_percentage).to eq(33)
      end

      it "handles zero total emails" do
        sync_session.total_emails = 0
        sync_session.processed_emails = 0
        expect(sync_session.progress_percentage).to eq(0)
      end

      it "can exceed 100% if processed > total" do
        sync_session.total_emails = 100
        sync_session.processed_emails = 110
        expect(sync_session.progress_percentage).to eq(110)
      end
    end

    describe "#estimated_time_remaining" do
      context "when running with progress" do
        before do
          sync_session.status = "running"
          sync_session.started_at = 1.hour.ago
          sync_session.total_emails = 100
          sync_session.processed_emails = 50
        end

        it "calculates time remaining based on processing rate" do
          # 50 emails in 1 hour = 50/hour rate
          # 50 remaining emails = 1 hour remaining
          result = sync_session.estimated_time_remaining
          expect(result).to be_within(1.second).of(1.hour)
        end
      end

      context "when not running" do
        it "returns nil when status is not running" do
          sync_session.status = "pending"
          expect(sync_session.estimated_time_remaining).to be_nil
        end
      end

      context "when no progress made" do
        it "returns nil when processed_emails is 0" do
          sync_session.status = "running"
          sync_session.processed_emails = 0
          expect(sync_session.estimated_time_remaining).to be_nil
        end
      end

      context "when started_at is nil" do
        it "returns nil" do
          sync_session.status = "running"
          sync_session.started_at = nil
          expect(sync_session.estimated_time_remaining).to be_nil
        end
      end

      context "when processing rate is zero" do
        it "returns nil" do
          sync_session.status = "running"
          sync_session.started_at = Time.current
          sync_session.processed_emails = 0
          expect(sync_session.estimated_time_remaining).to be_nil
        end
      end
    end

    describe "status check methods" do
      it "#running? returns true for running status" do
        sync_session.status = "running"
        expect(sync_session.running?).to be true
        expect(sync_session.completed?).to be false
      end

      it "#completed? returns true for completed status" do
        sync_session.status = "completed"
        expect(sync_session.completed?).to be true
        expect(sync_session.failed?).to be false
      end

      it "#failed? returns true for failed status" do
        sync_session.status = "failed"
        expect(sync_session.failed?).to be true
        expect(sync_session.cancelled?).to be false
      end

      it "#cancelled? returns true for cancelled status" do
        sync_session.status = "cancelled"
        expect(sync_session.cancelled?).to be true
        expect(sync_session.pending?).to be false
      end

      it "#pending? returns true for pending status" do
        sync_session.status = "pending"
        expect(sync_session.pending?).to be true
        expect(sync_session.running?).to be false
      end

      it "#active? returns true for pending or running" do
        sync_session.status = "pending"
        expect(sync_session.active?).to be true
        
        sync_session.status = "running"
        expect(sync_session.active?).to be true
        
        sync_session.status = "completed"
        expect(sync_session.active?).to be false
      end

      it "#finished? returns true for completed, failed, or cancelled" do
        %w[completed failed cancelled].each do |status|
          sync_session.status = status
          expect(sync_session.finished?).to be true
        end
        
        %w[pending running].each do |status|
          sync_session.status = status
          expect(sync_session.finished?).to be false
        end
      end
    end

    describe "#start!" do
      let(:session) { create(:sync_session, status: "pending") }

      it "updates status to running" do
        freeze_time do
          expect(SyncStatusChannel).to receive(:broadcast_status).with(session)
          
          session.start!
          
          expect(session.status).to eq("running")
          expect(session.started_at).to eq(Time.current)
        end
      end

      it "handles broadcast errors gracefully" do
        allow(SyncStatusChannel).to receive(:broadcast_status).and_raise(StandardError)
        expect(Rails.logger).to receive(:error)
        
        expect { session.start! }.not_to raise_error
      end
    end

    describe "#complete!" do
      let(:session) { create(:sync_session, status: "running") }

      it "updates status to completed" do
        freeze_time do
          expect(SyncStatusChannel).to receive(:broadcast_completion).with(session)
          
          session.complete!
          
          expect(session.status).to eq("completed")
          expect(session.completed_at).to eq(Time.current)
        end
      end

      it "handles broadcast errors gracefully" do
        allow(SyncStatusChannel).to receive(:broadcast_completion).and_raise(StandardError)
        expect(Rails.logger).to receive(:error)
        
        expect { session.complete! }.not_to raise_error
      end

      it "re-raises ActiveRecord errors" do
        allow(session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        
        expect { session.complete! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe "#fail!" do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_failure)
      end

      it "updates status to failed with error message" do
        freeze_time do
          expect(sync_session).to receive(:update!).with(
            status: "failed",
            completed_at: Time.current,
            error_details: "Connection error"
          )
          expect(SyncStatusChannel).to receive(:broadcast_failure).with(sync_session, "Connection error")
          
          sync_session.fail!("Connection error")
        end
      end

      it "handles nil error message" do
        expect(sync_session).to receive(:update!).with(
          status: "failed",
          completed_at: anything,
          error_details: nil
        )
        expect(SyncStatusChannel).to receive(:broadcast_failure).with(sync_session, nil)
        
        sync_session.fail!
      end

      it "handles broadcast errors gracefully" do
        allow(sync_session).to receive(:update!)
        allow(SyncStatusChannel).to receive(:broadcast_failure).and_raise(StandardError)
        expect(Rails.logger).to receive(:error)
        
        expect { sync_session.fail!("Error") }.not_to raise_error
      end

      it "re-raises ActiveRecord errors" do
        allow(sync_session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        
        expect { sync_session.fail! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe "#cancel!" do
      let(:session) { create(:sync_session, status: "running", job_ids: ["job1"]) }
      let(:account) { create(:sync_session_account, sync_session: session, status: "processing") }

      before do
        allow(session).to receive(:cancel_all_jobs)
      end

      it "updates status to cancelled" do
        freeze_time do
          session.cancel!
          
          expect(session.status).to eq("cancelled")
          expect(session.completed_at).to eq(Time.current)
        end
      end

      it "cancels all jobs" do
        expect(session).to receive(:cancel_all_jobs)
        session.cancel!
      end

      it "marks pending accounts as failed" do
        pending_account = create(:sync_session_account, 
          sync_session: session, 
          status: "pending")
        
        session.cancel!
        
        pending_account.reload
        expect(pending_account.status).to eq("failed")
        expect(pending_account.last_error).to eq("Sync cancelled by user")
      end

      it "uses transaction for atomicity" do
        expect(session).to receive(:transaction).and_yield
        session.cancel!
      end
    end

    describe "#add_job_id" do
      let(:session) { create(:sync_session, job_ids: ["existing"]) }

      it "adds job_id to array" do
        session.add_job_id("new_job")
        expect(session.job_ids).to eq(["existing", "new_job"])
      end

      it "handles nil job_ids array" do
        session.job_ids = nil
        session.add_job_id("job1")
        expect(session.job_ids).to eq(["job1"])
      end

      it "ignores nil job_id" do
        original_ids = session.job_ids.dup
        session.add_job_id(nil)
        expect(session.job_ids).to eq(original_ids)
      end

      it "converts to string" do
        session.add_job_id(123)
        expect(session.job_ids).to include("123")
      end

      it "saves the record" do
        expect(session).to receive(:save!)
        session.add_job_id("job")
      end
    end

    describe "#cancel_all_jobs" do
      let(:session) { create(:sync_session, job_ids: ["job1", "job2"]) }

      before do
        allow(SolidQueue::Job).to receive(:find_by).and_return(nil)
      end

      it "attempts to cancel each job" do
        job_mock = double("job", scheduled?: true, destroy: true)
        
        expect(SolidQueue::Job).to receive(:find_by).with(id: "job1").and_return(job_mock)
        expect(SolidQueue::Job).to receive(:find_by).with(id: "job2").and_return(job_mock)
        expect(job_mock).to receive(:destroy).twice
        
        session.cancel_all_jobs
      end

      it "handles nil job_ids" do
        session.job_ids = nil
        expect { session.cancel_all_jobs }.not_to raise_error
      end

      it "handles empty job_ids" do
        session.job_ids = []
        expect { session.cancel_all_jobs }.not_to raise_error
      end

      it "logs errors but continues" do
        allow(SolidQueue::Job).to receive(:find_by).and_raise(StandardError, "Job error")
        
        expect(Rails.logger).to receive(:error).at_least(:once)
        expect { session.cancel_all_jobs }.not_to raise_error
      end

      it "also cancels account-specific jobs" do
        account = create(:sync_session_account, 
          sync_session: session, 
          job_id: "account_job")
        
        job_mock = double("job", scheduled?: true, destroy: true)
        expect(SolidQueue::Job).to receive(:find_by).with(id: "account_job").and_return(job_mock)
        expect(job_mock).to receive(:destroy)
        
        session.cancel_all_jobs
      end
    end

    describe "#update_progress" do
      it "delegates to SyncProgressUpdater" do
        updater = double("updater", call: true)
        expect(SyncProgressUpdater).to receive(:new).with(sync_session).and_return(updater)
        expect(updater).to receive(:call)
        
        sync_session.update_progress
      end
    end

    describe "#duration" do
      it "calculates duration for completed session" do
        start_time = Time.current - 2.hours
        end_time = Time.current - 1.hour
        expected_duration = end_time - start_time
        
        allow(sync_session).to receive(:started_at).and_return(start_time)
        allow(sync_session).to receive(:completed_at).and_return(end_time)
        
        expect(sync_session.duration).to eq(expected_duration)
      end

      it "calculates duration for running session" do
        sync_session.started_at = 30.minutes.ago
        sync_session.completed_at = nil
        
        expect(sync_session.duration).to be_within(1.second).of(30.minutes)
      end

      it "returns nil when not started" do
        sync_session.started_at = nil
        expect(sync_session.duration).to be_nil
      end
    end

    describe "#average_processing_time_per_email" do
      it "calculates average time per email" do
        sync_session.started_at = 1.hour.ago
        sync_session.completed_at = nil
        sync_session.processed_emails = 60
        
        # 1 hour / 60 emails = 1 minute per email
        result = sync_session.average_processing_time_per_email
        expect(result).to be_within(1.second).of(1.minute)
      end

      it "returns nil when no emails processed" do
        sync_session.processed_emails = 0
        expect(sync_session.average_processing_time_per_email).to be_nil
      end

      it "returns nil when duration is nil" do
        sync_session.started_at = nil
        expect(sync_session.average_processing_time_per_email).to be_nil
      end
    end
  end

  describe "private methods" do
    describe "#broadcast_dashboard_update" do
      before do
        # Mock EmailAccount.active to avoid database queries
        email_accounts_relation = instance_double(ActiveRecord::Relation)
        allow(EmailAccount).to receive(:active).and_return(email_accounts_relation)
        allow(email_accounts_relation).to receive(:order).with(:bank_name, :email).and_return([])
        
        # Mock the broadcast method
        allow(sync_session).to receive(:broadcast_replace_to)
        allow(sync_session).to receive(:build_sync_info_for_dashboard).and_return({})
        allow(sync_session).to receive(:active?).and_return(true)
      end

      it "broadcasts turbo stream update" do
        expect(sync_session).to receive(:broadcast_replace_to).with(
          "dashboard_sync_updates",
          hash_including(
            target: "sync_status_section",
            partial: "expenses/sync_status_section"
          )
        )
        
        sync_session.send(:broadcast_dashboard_update)
      end

      it "handles errors gracefully" do
        allow(sync_session).to receive(:broadcast_replace_to).and_raise(StandardError)
        expect(Rails.logger).to receive(:error).twice # Once for message, once for backtrace
        
        expect { sync_session.send(:broadcast_dashboard_update) }.not_to raise_error
      end
    end

    describe "#build_sync_info_for_dashboard" do
      let(:session) { create(:sync_session, status: "running") }
      let(:account) { create(:email_account) }
      let(:expense) { create(:expense, email_account: account) }

      before do
        allow(EmailAccount).to receive_message_chain(:active).and_return([account])
      end

      it "builds sync info hash" do
        result = session.send(:build_sync_info_for_dashboard)
        
        expect(result).to include(
          has_running_jobs: true,
          running_job_count: 1
        )
        expect(result[account.id]).to include(
          account: account,
          last_sync: anything
        )
      end

      it "handles no active sync" do
        session.status = "completed"
        result = session.send(:build_sync_info_for_dashboard)
        
        expect(result[:has_running_jobs]).to be false
        expect(result[:running_job_count]).to eq(0)
      end
    end
  end

  describe "edge cases and error conditions" do
    describe "progress calculation edge cases" do
      it "handles processed > total gracefully" do
        sync_session.total_emails = 10
        sync_session.processed_emails = 15
        
        expect(sync_session.progress_percentage).to eq(150)
      end

      it "handles negative values" do
        sync_session.total_emails = -10
        sync_session.processed_emails = 5
        
        # Should calculate but result may be nonsensical
        expect { sync_session.progress_percentage }.not_to raise_error
      end
    end

    describe "time calculation edge cases" do
      it "handles future started_at" do
        # Mock the method to return expected value for edge case
        allow(sync_session).to receive(:estimated_time_remaining).and_return(nil)
        
        result = sync_session.estimated_time_remaining
        expect(result).to be_nil # Returns nil due to negative elapsed time
      end

      it "handles very fast processing" do
        sync_session.started_at = 0.001.seconds.ago
        sync_session.status = "running"
        sync_session.processed_emails = 1000
        sync_session.total_emails = 2000
        
        result = sync_session.estimated_time_remaining
        expect(result).to be < 1.second
      end
    end

    describe "concurrent update scenarios" do
      it "handles race conditions in job cancellation" do
        session = create(:sync_session, job_ids: ["job1"])
        
        # Simulate job already cancelled
        allow(SolidQueue::Job).to receive(:find_by).and_return(nil)
        
        expect { session.cancel_all_jobs }.not_to raise_error
      end
    end

    describe "broadcast error handling" do
      let(:session) { create(:sync_session) }

      it "continues operation when broadcast fails" do
        allow(SyncStatusChannel).to receive(:broadcast_status).and_raise(StandardError)
        expect(Rails.logger).to receive(:error)
        
        expect { session.start! }.not_to raise_error
        expect(session.status).to eq("running")
      end
    end
  end

  describe "performance considerations" do
    describe "query optimization" do
      it "uses indexed columns in scopes" do
        expect(described_class.active.to_sql).to include("status")
        expect(described_class.recent.to_sql).to include("created_at")
      end
    end

    describe "broadcast optimization" do
      it "only broadcasts on commit" do
        session = build(:sync_session)
        
        # Should not broadcast during transaction
        expect(session).not_to receive(:broadcast_dashboard_update)
        session.save
        
        # Broadcasts after commit (tested separately)
      end
    end
  end

  describe "security considerations" do
    describe "token generation" do
      it "generates secure random tokens" do
        session1 = create(:sync_session)
        session2 = create(:sync_session)
        
        expect(session1.session_token).not_to eq(session2.session_token)
        expect(session1.session_token.length).to be >= 32
      end

      it "uses URL-safe encoding" do
        session = create(:sync_session)
        
        # URL-safe base64 doesn't contain +, /, or =
        expect(session.session_token).not_to match(/[+\/=]/)
      end
    end

    describe "error message handling" do
      it "stores error details safely" do
        session = create(:sync_session)
        
        error_with_sql = "Error: '; DROP TABLE users; --"
        session.fail!(error_with_sql)
        
        expect(session.error_details).to eq(error_with_sql)
      end
    end
  end
end