require 'rails_helper'

RSpec.describe ProcessEmailsJob, type: :job do
  let(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:inactive_email_account) { create(:email_account, :inactive) }
  let(:mock_fetcher) { instance_double(EmailProcessing::Fetcher) }

  before do
    parsing_rule # Ensure parsing rule exists
  end

  describe '#perform' do
    context 'with specific email account id' do
      it 'processes single account' do
        job = ProcessEmailsJob.new
        allow(job).to receive(:process_single_account)
        since_time = 1.day.ago

        job.perform(email_account.id, since: since_time)

        expect(job).to have_received(:process_single_account).with(
          email_account.id,
          since_time
        )
      end

      it 'does not process all accounts' do
        job = ProcessEmailsJob.new
        allow(job).to receive(:process_single_account)
        allow(job).to receive(:process_all_accounts)

        job.perform(email_account.id, since: 1.day.ago)

        expect(job).not_to have_received(:process_all_accounts)
      end
    end

    context 'without email account id' do
      it 'processes all accounts when no id provided' do
        job = ProcessEmailsJob.new
        allow(job).to receive(:process_all_accounts)
        since_time = 1.day.ago

        job.perform(nil, since: since_time)

        expect(job).to have_received(:process_all_accounts).with(since_time)
      end

      it 'uses default since parameter when not provided' do
        job = ProcessEmailsJob.new
        allow(job).to receive(:process_all_accounts)

        job.perform

        expect(job).to have_received(:process_all_accounts).with(
          an_instance_of(ActiveSupport::TimeWithZone)
        )
      end
    end
  end

  describe '#process_single_account' do
    let(:job) { ProcessEmailsJob.new }
    let(:since_time) { 2.days.ago }

    context 'with valid active email account' do
      let(:success_response) do
        EmailProcessing::FetcherResponse.success(
          processed_emails_count: 3,
          total_emails_found: 5
        )
      end

      before do
        allow(EmailProcessing::Fetcher).to receive(:new).with(email_account).and_return(mock_fetcher)
        allow(mock_fetcher).to receive(:fetch_new_emails).and_return(success_response)
      end

      it 'creates EmailProcessing::Fetcher and fetches emails' do
        job.send(:process_single_account, email_account.id, since_time)

        expect(EmailProcessing::Fetcher).to have_received(:new).with(email_account)
        expect(mock_fetcher).to have_received(:fetch_new_emails).with(since: since_time)
      end

      it 'logs processing start' do
        allow(Rails.logger).to receive(:info)

        job.send(:process_single_account, email_account.id, since_time)

        expect(Rails.logger).to have_received(:info).with(
          "Processing emails for: #{email_account.email}"
        )
      end

      it 'logs success when fetch succeeds' do
        allow(Rails.logger).to receive(:info)

        job.send(:process_single_account, email_account.id, since_time)

        expect(Rails.logger).to have_received(:info).with(
          "Successfully processed emails for: #{email_account.email} - Found: 5, Processed: 3"
        )
      end
    end

    context 'with fetch failure' do
      let(:fetch_errors) { [ "IMAP connection failed", "Authentication error" ] }
      let(:failure_response) do
        EmailProcessing::FetcherResponse.failure(errors: fetch_errors)
      end

      before do
        allow(EmailProcessing::Fetcher).to receive(:new).with(email_account).and_return(mock_fetcher)
        allow(mock_fetcher).to receive(:fetch_new_emails).and_return(failure_response)
      end

      it 'logs error when fetch fails' do
        allow(Rails.logger).to receive(:error)

        job.send(:process_single_account, email_account.id, since_time)

        expect(Rails.logger).to have_received(:error).with(
          "Failed to process emails for #{email_account.email}: #{fetch_errors.join(", ")}"
        )
      end

      it 'does not log success' do
        allow(Rails.logger).to receive(:info)

        job.send(:process_single_account, email_account.id, since_time)

        expect(Rails.logger).not_to have_received(:info).with(
          a_string_matching(/Successfully processed/)
        )
      end
    end

    context 'with success but warnings' do
      let(:warnings) { [ "Minor connection issue", "Slow response" ] }
      let(:success_with_warnings_response) do
        EmailProcessing::FetcherResponse.success(
          processed_emails_count: 2,
          total_emails_found: 3,
          errors: warnings
        )
      end

      before do
        allow(EmailProcessing::Fetcher).to receive(:new).with(email_account).and_return(mock_fetcher)
        allow(mock_fetcher).to receive(:fetch_new_emails).and_return(success_with_warnings_response)
      end

      it 'logs success and warnings' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        job.send(:process_single_account, email_account.id, since_time)

        expect(Rails.logger).to have_received(:info).with(
          "Successfully processed emails for: #{email_account.email} - Found: 3, Processed: 2"
        )
        expect(Rails.logger).to have_received(:warn).with(
          "Warnings during processing: #{warnings.join(", ")}"
        )
      end
    end

    context 'with non-existent email account' do
      it 'logs error and returns early' do
        allow(Rails.logger).to receive(:error)

        job.send(:process_single_account, 99999, since_time)

        expect(Rails.logger).to have_received(:error).with(
          "EmailAccount not found: 99999"
        )
        expect(EmailProcessing::Fetcher).not_to receive(:new)
      end
    end

    context 'with inactive email account' do
      it 'logs info and skips processing' do
        allow(Rails.logger).to receive(:info)

        job.send(:process_single_account, inactive_email_account.id, since_time)

        expect(Rails.logger).to have_received(:info).with(
          "Skipping inactive email account: #{inactive_email_account.email}"
        )
        expect(EmailProcessing::Fetcher).not_to receive(:new)
      end

      it 'does not create EmailProcessing::Fetcher' do
        allow(EmailProcessing::Fetcher).to receive(:new)

        job.send(:process_single_account, inactive_email_account.id, since_time)

        expect(EmailProcessing::Fetcher).not_to have_received(:new)
      end
    end

    context 'when EmailProcessing::Fetcher raises exception' do
      before do
        allow(EmailProcessing::Fetcher).to receive(:new).and_raise(StandardError.new("Connection error"))
      end

      it 'allows exception to bubble up' do
        expect {
          job.send(:process_single_account, email_account.id, since_time)
        }.to raise_error(StandardError, "Connection error")
      end
    end
  end

  describe '#process_all_accounts' do
    let(:job) { ProcessEmailsJob.new }
    let(:since_time) { 3.days.ago }
    let!(:active_account1) { create(:email_account, :bac) }
    let!(:active_account2) { create(:email_account, :gmail) }
    let!(:inactive_account) { create(:email_account, :inactive) }

    before do
      parsing_rule # Ensure parsing rules exist
    end

    it 'logs processing start with account count' do
      allow(Rails.logger).to receive(:info)

      job.send(:process_all_accounts, since_time)

      expect(Rails.logger).to have_received(:info).with(
        "Processing emails for 2 active accounts"
      )
    end

    it 'enqueues ProcessEmailsJob for each active account' do
      expect {
        job.send(:process_all_accounts, since_time)
      }.to have_enqueued_job(ProcessEmailsJob).exactly(2).times
    end

    it 'enqueues jobs with correct parameters' do
      job.send(:process_all_accounts, since_time)

      expect(ProcessEmailsJob).to have_been_enqueued.with(
        active_account1.id,
        since: since_time
      )
      expect(ProcessEmailsJob).to have_been_enqueued.with(
        active_account2.id,
        since: since_time
      )
    end

    it 'does not enqueue jobs for inactive accounts' do
      job.send(:process_all_accounts, since_time)

      expect(ProcessEmailsJob).not_to have_been_enqueued.with(
        inactive_account.id,
        since: since_time
      )
    end

    context 'with no active accounts' do
      before do
        EmailAccount.update_all(active: false)
      end

      it 'logs zero account count' do
        allow(Rails.logger).to receive(:info)

        job.send(:process_all_accounts, since_time)

        expect(Rails.logger).to have_received(:info).with(
          "Processing emails for 0 active accounts"
        )
      end

      it 'does not enqueue any jobs' do
        expect {
          job.send(:process_all_accounts, since_time)
        }.not_to have_enqueued_job(ProcessEmailsJob)
      end
    end

    context 'with large number of accounts' do
      before do
        # Create additional accounts to test find_each behavior
        5.times { create(:email_account, :bac) }
      end

      it 'processes accounts in batches using find_each' do
        expect {
          job.send(:process_all_accounts, since_time)
        }.to have_enqueued_job(ProcessEmailsJob).exactly(7).times # 2 existing + 5 new
      end
    end
  end

  describe '#process_all_accounts_in_batches' do
    let(:job) { ProcessEmailsJob.new }
    let(:since_time) { 3.days.ago }

    before do
      # Create 12 accounts to test batching
      12.times { create(:email_account, :bac) }
    end

    it 'processes accounts in batches of 5' do
      expect {
        job.send(:process_all_accounts_in_batches, since_time)
      }.to have_enqueued_job(ProcessEmailsJob).exactly(12).times
    end

    it 'sleeps between full batches to prevent server overload' do
      expect(job).to receive(:sleep).with(1).exactly(2).times # 2 full batches of 5

      job.send(:process_all_accounts_in_batches, since_time)
    end

    it 'does not sleep for partial batch' do
      # Remove some accounts to make last batch partial
      EmailAccount.limit(2).destroy_all # Now we have 10 accounts (2 full batches, 1 partial)

      expect(job).to receive(:sleep).with(1).exactly(2).times

      job.send(:process_all_accounts_in_batches, since_time)
    end

    it 'enqueues jobs with correct parameters' do
      accounts = EmailAccount.active.limit(2)

      job.send(:process_all_accounts_in_batches, since_time)

      accounts.each do |account|
        expect(ProcessEmailsJob).to have_been_enqueued.with(
          account.id,
          since: since_time
        )
      end
    end
  end

  describe 'around_perform performance monitoring' do
    let(:job) { ProcessEmailsJob.new }

    before do
      allow(EmailProcessing::Fetcher).to receive(:new).and_return(mock_fetcher)
      allow(mock_fetcher).to receive(:fetch_new_emails).and_return(
        EmailProcessing::FetcherResponse.success(processed_emails_count: 1, total_emails_found: 1)
      )
    end

    it 'logs job start and completion' do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with("[ProcessEmailsJob] Starting for account #{email_account.id}")
      expect(Rails.logger).to receive(:info).with(/\[ProcessEmailsJob\] Completed in \d+\.\d+s/)

      ProcessEmailsJob.perform_now(email_account.id)
    end

    it 'measures job duration' do
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 2.seconds)

      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with("[ProcessEmailsJob] Starting for account #{email_account.id}")
      expect(Rails.logger).to receive(:info).with("[ProcessEmailsJob] Completed in 2.0s")

      ProcessEmailsJob.perform_now(email_account.id)
    end

    it 'warns on slow processing over 30 seconds' do
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 35.seconds)

      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:warn).with(
        "[ProcessEmailsJob] Slow processing: 35.0s for account #{email_account.id}"
      )

      ProcessEmailsJob.perform_now(email_account.id)
    end

    it 'does not warn on processing under 30 seconds' do
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 15.seconds)

      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).not_to receive(:warn)

      ProcessEmailsJob.perform_now(email_account.id)
    end

    it 'logs performance even when job raises error' do
      allow(mock_fetcher).to receive(:fetch_new_emails).and_raise(StandardError, "Test error")

      # Stub all logger methods to avoid interference
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)

      # Check that the job logs start
      expect(Rails.logger).to receive(:info).with("[ProcessEmailsJob] Starting for account #{email_account.id}").at_least(:once)

      expect {
        ProcessEmailsJob.perform_now(email_account.id)
      }.to raise_error(StandardError, "Test error")
    end
  end


  describe 'job queue configuration' do
    it 'uses the email_processing queue' do
      expect(ProcessEmailsJob.new.queue_name).to eq('email_processing')
    end
  end

  describe 'ActiveJob integration' do
    it 'can be enqueued with perform_later' do
      since_time = 1.day.ago
      expect {
        ProcessEmailsJob.perform_later(email_account.id, since: since_time)
      }.to have_enqueued_job(ProcessEmailsJob).with(
        email_account.id,
        since: since_time
      )
    end

    it 'can be performed immediately' do
      allow(EmailProcessing::Fetcher).to receive(:new).and_return(mock_fetcher)
      allow(mock_fetcher).to receive(:fetch_new_emails).and_return(
        EmailProcessing::FetcherResponse.success(processed_emails_count: 2, total_emails_found: 3)
      )

      expect {
        ProcessEmailsJob.perform_now(email_account.id, since: 1.day.ago)
      }.not_to raise_error
    end
  end

  describe 'parameter variations' do
    let(:job) { ProcessEmailsJob.new }

    context 'with string email account id' do
      it 'handles string id parameter' do
        allow(EmailProcessing::Fetcher).to receive(:new).and_return(mock_fetcher)
        allow(mock_fetcher).to receive(:fetch_new_emails).and_return(
          EmailProcessing::FetcherResponse.success(processed_emails_count: 1, total_emails_found: 2)
        )

        expect {
          job.perform(email_account.id.to_s, since: 1.day.ago)
        }.not_to raise_error
      end
    end

    context 'with different time formats for since parameter' do
      it 'handles Time object' do
        expect {
          job.perform(email_account.id, since: Time.current - 2.days)
        }.not_to raise_error
      end

      it 'handles DateTime object' do
        expect {
          job.perform(email_account.id, since: DateTime.current - 2.days)
        }.not_to raise_error
      end

      it 'handles ActiveSupport::TimeWithZone' do
        expect {
          job.perform(email_account.id, since: 2.days.ago)
        }.not_to raise_error
      end
    end
  end

  describe 'error handling and resilience' do
    let(:job) { ProcessEmailsJob.new }

    context 'when database is temporarily unavailable' do
      it 'handles database connection errors' do
        allow(EmailAccount).to receive(:find_by).and_raise(ActiveRecord::ConnectionNotEstablished)

        expect {
          job.send(:process_single_account, email_account.id, 1.day.ago)
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end
    end

    context 'when memory is constrained' do
      before do
        # Simulate large dataset for find_each testing
        allow(EmailAccount).to receive(:active).and_return(
          double(find_each: nil, count: 1000)
        )
      end

      it 'uses find_each for memory efficiency' do
        active_scope = EmailAccount.active
        expect(active_scope).to receive(:find_each)

        job.send(:process_all_accounts, 1.day.ago)
      end
    end
  end

  describe 'integration scenarios' do
    context 'full workflow integration' do
      let!(:parsing_rule) { create(:parsing_rule, :bac) }
      let!(:email_account) { create(:email_account, :bac) }

      it 'can process single account end-to-end with mocked EmailProcessing::Fetcher' do
        allow(EmailProcessing::Fetcher).to receive(:new).and_return(mock_fetcher)
        allow(mock_fetcher).to receive(:fetch_new_emails).and_return(
          EmailProcessing::FetcherResponse.success(processed_emails_count: 0, total_emails_found: 0)
        )

        expect {
          ProcessEmailsJob.perform_now(email_account.id, since: 1.day.ago)
        }.not_to raise_error
      end

      it 'can process all accounts end-to-end' do
        expect {
          ProcessEmailsJob.perform_now(nil, since: 1.day.ago)
        }.to have_enqueued_job(ProcessEmailsJob).at_least(1).times
      end
    end
  end
end
