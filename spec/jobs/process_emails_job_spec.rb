# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessEmailsJob, type: :job, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:sync_session) { create(:sync_session, status: "pending") }

  # Mock dependencies
  let(:mock_fetcher) { instance_double(EmailProcessing::Fetcher) }
  let(:mock_metrics_collector) { instance_double(SyncMetricsCollector) }
  let(:success_response) { EmailProcessing::FetcherResponse.success(processed_emails_count: 5, total_emails_found: 10) }

  before do
    # Setup basic mocks
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    allow(SyncMetricsCollector).to receive(:new).and_return(mock_metrics_collector)
    allow(mock_metrics_collector).to receive(:track_operation).and_yield
    allow(mock_metrics_collector).to receive(:record_session_metrics)
    allow(mock_metrics_collector).to receive(:flush_buffer)

    allow(EmailProcessing::Fetcher).to receive(:new).and_return(mock_fetcher)
    allow(mock_fetcher).to receive(:fetch_new_emails).and_return(success_response)
  end

  describe "job configuration" do
    it "uses email_processing queue", :unit do
      expect(described_class.queue_name).to eq("email_processing")
    end

    it "inherits from ApplicationJob", :unit do
      expect(described_class.superclass).to eq(ApplicationJob)
    end

    it "has retry configuration for connection errors", :unit do
      rescue_handlers = described_class.rescue_handlers
      handler_classes = rescue_handlers.map(&:first)

      expect(handler_classes).to include("ImapConnectionService::ConnectionError")
      expect(handler_classes).to include("Net::ReadTimeout")
    end
  end

  describe "#perform" do
    context "with valid email account" do
      it "processes single account successfully", :unit do
        job = described_class.new

        expect { job.perform(email_account.id) }.not_to raise_error
        expect(Rails.logger).to have_received(:info).with(/Processing emails for/)
      end

      it "processes with sync session", :unit do
        job = described_class.new

        expect { job.perform(email_account.id, sync_session_id: sync_session.id) }.not_to raise_error
      end
    end

    context "without email account id" do
      it "processes all accounts", :unit do
        allow(EmailAccount).to receive(:active).and_return(EmailAccount.where(id: email_account.id))
        allow_any_instance_of(described_class).to receive(:process_all_accounts)

        job = described_class.new

        expect { job.perform }.not_to raise_error
      end
    end

    context "with sync session validation" do
      it "starts pending sync session", :unit do
        allow(SyncSession).to receive(:find_by).with(id: sync_session.id).and_return(sync_session)
        expect(sync_session).to receive(:start!)

        job = described_class.new
        job.perform(email_account.id, sync_session_id: sync_session.id)
      end

      it "handles non-existent sync session", :unit do
        job = described_class.new

        expect { job.perform(email_account.id, sync_session_id: 999999) }.not_to raise_error
      end
    end

    context "error handling" do
      it "handles ActiveRecord::RecordNotFound", :unit do
        allow(EmailAccount).to receive(:find_by).and_raise(ActiveRecord::RecordNotFound.new("Account not found"))

        job = described_class.new

        expect { job.perform(email_account.id) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/Record not found/)
      end

      it "handles StandardError and re-raises", :unit do
        allow(mock_fetcher).to receive(:fetch_new_emails).and_raise(StandardError.new("Test error"))

        job = described_class.new

        expect { job.perform(email_account.id) }.to raise_error(StandardError, "Test error")
        expect(Rails.logger).to have_received(:error).with(/Unexpected error/)
      end
    end
  end

  describe "around_perform callback" do
    it "logs processing information", :unit do
      job = described_class.new
      job.perform(email_account.id)

      # Verify that the job processes and logs information (indirect verification)
      expect(Rails.logger).to have_received(:info).at_least(:once)
    end

    it "can handle performance monitoring", :unit do
      job = described_class.new

      # Test that the job completes without error when timing callbacks are present
      expect { job.perform(email_account.id) }.not_to raise_error
    end
  end

  describe "#process_single_account" do
    let(:job) { described_class.new }

    it "finds and processes account", :unit do
      allow(EmailAccount).to receive(:find_by).with(id: email_account.id).and_return(email_account)

      expect { job.send(:process_single_account, email_account.id, 1.week.ago) }.not_to raise_error
    end

    it "handles missing account", :unit do
      allow(EmailAccount).to receive(:find_by).with(id: 999999).and_return(nil)

      expect { job.send(:process_single_account, 999999, 1.week.ago) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/EmailAccount not found/)
    end

    it "handles inactive account", :unit do
      inactive_account = create(:email_account, :inactive)
      allow(EmailAccount).to receive(:find_by).with(id: inactive_account.id).and_return(inactive_account)

      expect { job.send(:process_single_account, inactive_account.id, 1.week.ago) }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with(/Skipping inactive email account/)
    end
  end

  describe "#process_all_accounts" do
    let(:job) { described_class.new }

    it "enqueues jobs for active accounts", :unit do
      active_accounts = [ email_account ]
      active_relation = double("ActiveRecord::Relation")
      allow(active_relation).to receive(:count).and_return(1)
      allow(active_relation).to receive(:find_each).and_yield(email_account)
      allow(EmailAccount).to receive(:active).and_return(active_relation)
      allow(described_class).to receive(:perform_later).and_return(double(provider_job_id: "123"))

      expect(described_class).to receive(:perform_later).once

      job.send(:process_all_accounts, 1.week.ago)
    end
  end

  describe "ActiveJob integration" do
    it "can be enqueued", :unit do
      expect { described_class.perform_later(email_account.id) }.to have_enqueued_job(described_class)
    end

    it "can be performed immediately", :unit do
      expect { described_class.perform_now(email_account.id) }.not_to raise_error
    end
  end
end
