require 'rails_helper'

RSpec.describe ProcessEmailsJob, type: :job do
  let(:email_account) { create(:email_account) }
  let(:sync_session) { create(:sync_session, :running) }
  let!(:sync_account) do
    create(:sync_session_account,
           sync_session: sync_session,
           email_account: email_account,
           status: 'pending')
  end

  describe "job execution" do
    context "with successful email processing" do
      before do
        # Mock IMAP service to return successful result
        success_response = EmailProcessing::FetcherResponse.success(
          processed_emails_count: 3,
          total_emails_found: 3,
          errors: []
        )
        allow_any_instance_of(EmailProcessing::Fetcher).to receive(:fetch_new_emails).and_return(success_response)
      end

      it "processes emails successfully without errors" do
        expect {
          ProcessEmailsJob.perform_now(email_account.id, sync_session_id: sync_session.id)
        }.not_to raise_error

        sync_account.reload
        expect(sync_account.status).to eq('completed')
      end

      it "handles email account not found gracefully" do
        expect {
          ProcessEmailsJob.perform_now(99999, sync_session_id: sync_session.id)
        }.not_to raise_error
      end
    end

    context "with IMAP connection errors" do
      before do
        error_response = EmailProcessing::FetcherResponse.failure(
          errors: [ "IMAP Error: Connection failed" ]
        )
        allow_any_instance_of(EmailProcessing::Fetcher).to receive(:fetch_new_emails).and_return(error_response)
      end

      it "handles connection errors gracefully" do
        expect {
          ProcessEmailsJob.perform_now(email_account.id, sync_session_id: sync_session.id)
        }.not_to raise_error

        sync_account.reload
        expect(sync_account.status).to eq('failed')
        expect(sync_account.last_error).to include('IMAP Error: Connection failed')
      end
    end
  end
end
