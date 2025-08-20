require 'rails_helper'

RSpec.describe EmailProcessing::Fetcher, type: :service, integration: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }
  let(:mock_email_processor) { instance_double(EmailProcessing::Processor) }
  let(:fetcher) { EmailProcessing::Fetcher.new(email_account, imap_service: mock_imap_service, email_processor: mock_email_processor) }

  before do
    allow(mock_imap_service).to receive(:errors).and_return([])
    allow(mock_email_processor).to receive(:errors).and_return([])
  end

  describe '#initialize', integration: true do
    it 'sets the email account and initializes empty errors' do
      expect(fetcher.email_account).to eq(email_account)
      expect(fetcher.errors).to be_empty
      expect(fetcher.imap_service).to eq(mock_imap_service)
      expect(fetcher.email_processor).to eq(mock_email_processor)
    end

    it 'creates default services if none provided' do
      default_fetcher = EmailProcessing::Fetcher.new(email_account)
      expect(default_fetcher.imap_service).to be_a(ImapConnectionService)
      expect(default_fetcher.email_processor).to be_a(EmailProcessing::Processor)
    end
  end

  describe '#fetch_new_emails', integration: true do
    context 'with valid account' do
      let(:message_ids) { [ 1, 2 ] }

      before do
        allow(fetcher).to receive(:valid_account?).and_return(true)
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(mock_email_processor).to receive(:process_emails).and_return({ processed_count: 2, total_count: 2 })
      end

      it 'successfully fetches and processes emails' do
        result = fetcher.fetch_new_emails(since: 1.day.ago)

        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(2)
        expect(result.total_emails_found).to eq(2)
      end

      it 'builds search criteria and searches emails' do
        since_date = 2.days.ago
        expect(mock_imap_service).to receive(:search_emails).with([ 'SINCE', since_date.strftime('%d-%b-%Y') ])

        fetcher.fetch_new_emails(since: since_date)
      end

      it 'uses default since of 1 week ago' do
        expect(mock_imap_service).to receive(:search_emails)
        fetcher.fetch_new_emails
      end

      it 'handles empty message list' do
        allow(mock_imap_service).to receive(:search_emails).and_return([])
        allow(mock_email_processor).to receive(:process_emails).and_return({ processed_count: 0, total_count: 0 })

        result = fetcher.fetch_new_emails
        expect(result.success?).to be true
        expect(result.processed_emails_count).to eq(0)
        expect(result.total_emails_found).to eq(0)
      end
    end

    context 'with invalid account' do
      before do
        allow(fetcher).to receive(:valid_account?).and_return(false)
      end

      it 'returns failure response without attempting connection' do
        expect(mock_imap_service).not_to receive(:search_emails)
        result = fetcher.fetch_new_emails
        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.failure?).to be true
      end
    end

    context 'with IMAP errors' do
      before do
        allow(fetcher).to receive(:valid_account?).and_return(true)
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(ImapConnectionService::ConnectionError, 'Connection failed')
      end

      it 'handles IMAP connection errors gracefully' do
        result = fetcher.fetch_new_emails
        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.failure?).to be true
        expect(result.errors).to include('IMAP Error: Connection failed')
      end
    end

    context 'with authentication errors' do
      before do
        allow(fetcher).to receive(:valid_account?).and_return(true)
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(ImapConnectionService::AuthenticationError, 'Auth failed')
      end

      it 'handles IMAP authentication errors gracefully' do
        result = fetcher.fetch_new_emails
        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.failure?).to be true
        expect(result.errors).to include('IMAP Error: Auth failed')
      end
    end

    context 'with unexpected errors' do
      before do
        allow(fetcher).to receive(:valid_account?).and_return(true)
        allow(mock_imap_service).to receive(:search_emails)
          .and_raise(StandardError, 'Unexpected error')
      end

      it 'handles standard errors gracefully' do
        result = fetcher.fetch_new_emails
        expect(result).to be_a(EmailProcessing::FetcherResponse)
        expect(result.failure?).to be true
        expect(result.errors).to include('Unexpected error: Unexpected error')
      end
    end
  end

  describe 'private methods', integration: true do
    describe '#valid_account?', integration: true do
      context 'with valid account' do
        it 'returns true' do
          expect(fetcher.send(:valid_account?)).to be true
        end
      end

      context 'with inactive account' do
        before { email_account.update(active: false) }

        it 'returns false and adds error' do
          result = fetcher.send(:valid_account?)
          expect(result).to be false
          expect(fetcher.errors).to include('Email account is not active')
        end
      end

      context 'with missing password' do
        before { allow(email_account).to receive(:encrypted_password).and_return(nil) }

        it 'returns false and adds error' do
          result = fetcher.send(:valid_account?)
          expect(result).to be false
          expect(fetcher.errors).to include('Email account missing password')
        end
      end

      context 'with blank account' do
        let(:fetcher) { EmailProcessing::Fetcher.new(nil, imap_service: mock_imap_service, email_processor: mock_email_processor) }

        it 'returns false and adds error' do
          result = fetcher.send(:valid_account?)
          expect(result).to be false
          expect(fetcher.errors).to include('Email account not provided')
        end
      end
    end

    describe '#search_and_process_emails', integration: true do
      let(:message_ids) { [ 1, 2 ] }
      let(:since_date) { 1.day.ago }

      before do
        allow(mock_imap_service).to receive(:search_emails).and_return(message_ids)
        allow(mock_email_processor).to receive(:process_emails).and_return({ processed_count: 2, total_count: 2 })
      end

      it 'searches emails and delegates processing' do
        expect(mock_imap_service).to receive(:search_emails).with([ 'SINCE', since_date.strftime('%d-%b-%Y') ])
        expect(mock_email_processor).to receive(:process_emails).with(message_ids, mock_imap_service)

        result = fetcher.send(:search_and_process_emails, since_date)
        expect(result[:processed_emails_count]).to eq(2)
        expect(result[:total_emails_found]).to eq(2)
      end

      it 'does not log the number of emails found' do
        expect(Rails.logger).not_to receive(:info).with("[EmailProcessing::Fetcher] Found 2 emails for #{email_account.email}")
        fetcher.send(:search_and_process_emails, since_date)
      end
    end

    describe '#build_search_criteria', integration: true do
      it 'creates SINCE criteria with formatted date' do
        since_date = Date.new(2025, 1, 15)
        criteria = fetcher.send(:build_search_criteria, since_date)
        expect(criteria).to eq([ 'SINCE', '15-Jan-2025' ])
      end
    end

    describe '#add_error', integration: true do
      it 'adds error to the errors array' do
        fetcher.send(:add_error, 'Test error')
        expect(fetcher.errors).to include('Test error')
      end

      it 'logs the error with email account info' do
        expect(Rails.logger).to receive(:error).with("[EmailProcessing::Fetcher] #{email_account.email}: Test error")
        fetcher.send(:add_error, 'Test error')
      end

      it 'handles nil email account gracefully' do
        nil_fetcher = EmailProcessing::Fetcher.new(nil, imap_service: mock_imap_service, email_processor: mock_email_processor)
        expect(Rails.logger).to receive(:error).with("[EmailProcessing::Fetcher] Unknown: Test error")
        nil_fetcher.send(:add_error, 'Test error')
      end
    end
  end
end
