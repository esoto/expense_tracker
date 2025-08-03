require 'rails_helper'

RSpec.describe ImapConnectionService do
  let(:email_account) { create(:email_account, :bac) }
  let(:service) { described_class.new(email_account) }
  let(:mock_imap) { instance_double(Net::IMAP) }

  describe '#initialize' do
    it 'sets email account and initializes empty errors' do
      expect(service.email_account).to eq(email_account)
      expect(service.errors).to be_empty
    end
  end

  describe '#test_connection' do
    context 'when connection succeeds' do
      it 'returns true for successful connection test' do
        allow(service).to receive(:with_connection).and_yield(mock_imap)
        allow(mock_imap).to receive(:list).with("", "*").and_return(['INBOX'])

        result = service.test_connection

        expect(result).to be true
      end
    end

    context 'when connection fails' do
      it 'returns false and logs error for IMAP errors' do
        allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Connection refused")

        result = service.test_connection

        expect(result).to be false
        expect(service.errors).to include("Connection failed: Connection refused")
      end
    end
  end

  describe '#search_emails' do
    let(:search_criteria) { ["SINCE", "01-Jan-2025"] }

    context 'when search succeeds' do
      it 'returns message IDs from search' do
        allow(service).to receive(:with_connection).and_yield(mock_imap)
        allow(mock_imap).to receive(:search).with(search_criteria).and_return([1, 2, 3])

        result = service.search_emails(search_criteria)

        expect(result).to eq([1, 2, 3])
      end
    end

    context 'when search fails' do
      it 'returns empty array and logs error' do
        allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Search failed")

        result = service.search_emails(search_criteria)

        expect(result).to eq([])
        expect(service.errors).to include("Search failed: Search failed")
      end
    end
  end

  describe '#fetch_envelope' do
    let(:message_id) { 123 }
    let(:mock_envelope) { double('envelope', subject: 'Test Subject') }

    context 'when fetch succeeds' do
      it 'returns envelope data' do
        mock_fetch_result = double('fetch_result', attr: { "ENVELOPE" => mock_envelope })
        mock_fetch_array = [mock_fetch_result]

        allow(service).to receive(:with_connection).and_yield(mock_imap)
        allow(mock_imap).to receive(:fetch).with(message_id, "ENVELOPE").and_return(mock_fetch_array)

        result = service.fetch_envelope(message_id)

        expect(result).to eq(mock_envelope)
      end
    end

    context 'when fetch fails' do
      it 'returns nil and logs error' do
        allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Fetch failed")

        result = service.fetch_envelope(message_id)

        expect(result).to be_nil
        expect(service.errors).to include("Failed to fetch envelope for message 123: Fetch failed")
      end
    end
  end

  describe '#fetch_body_structure' do
    let(:message_id) { 123 }
    let(:mock_structure) { double('structure', multipart?: true) }

    it 'returns body structure data when successful' do
      mock_fetch_result = double('fetch_result', attr: { "BODYSTRUCTURE" => mock_structure })
      mock_fetch_array = [mock_fetch_result]

      allow(service).to receive(:with_connection).and_yield(mock_imap)
      allow(mock_imap).to receive(:fetch).with(message_id, "BODYSTRUCTURE").and_return(mock_fetch_array)

      result = service.fetch_body_structure(message_id)

      expect(result).to eq(mock_structure)
    end

    it 'returns nil and logs error when fetch fails' do
      allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Structure fetch failed")

      result = service.fetch_body_structure(message_id)

      expect(result).to be_nil
      expect(service.errors).to include("Failed to fetch body structure for message 123: Structure fetch failed")
    end
  end

  describe '#fetch_body_part' do
    let(:message_id) { 123 }
    let(:part_number) { "1" }
    let(:body_content) { "Email body content" }

    it 'returns body part content when successful' do
      mock_fetch_result = double('fetch_result', attr: { "BODY[1]" => body_content })
      mock_fetch_array = [mock_fetch_result]

      allow(service).to receive(:with_connection).and_yield(mock_imap)
      allow(mock_imap).to receive(:fetch).with(message_id, "BODY[1]").and_return(mock_fetch_array)

      result = service.fetch_body_part(message_id, part_number)

      expect(result).to eq(body_content)
    end

    it 'returns nil and logs error when fetch fails' do
      allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Body part fetch failed")

      result = service.fetch_body_part(message_id, part_number)

      expect(result).to be_nil
      expect(service.errors).to include("Failed to fetch body part 1 for message 123: Body part fetch failed")
    end
  end

  describe '#fetch_text_body' do
    let(:message_id) { 123 }
    let(:text_content) { "Plain text email content" }

    it 'returns text body content when successful' do
      mock_fetch_result = double('fetch_result', attr: { "BODY[TEXT]" => text_content })
      mock_fetch_array = [mock_fetch_result]

      allow(service).to receive(:with_connection).and_yield(mock_imap)
      allow(mock_imap).to receive(:fetch).with(message_id, "BODY[TEXT]").and_return(mock_fetch_array)

      result = service.fetch_text_body(message_id)

      expect(result).to eq(text_content)
    end

    it 'returns nil and logs error when fetch fails' do
      allow(service).to receive(:with_connection).and_raise(Net::IMAP::Error, "Text body fetch failed")

      result = service.fetch_text_body(message_id)

      expect(result).to be_nil
      expect(service.errors).to include("Failed to fetch text body for message 123: Text body fetch failed")
    end
  end

  describe '#with_connection' do
    let(:mock_settings) do
      {
        address: 'imap.test.com',
        port: 993,
        enable_ssl: true,
        user_name: 'test@test.com',
        password: 'password123'
      }
    end

    before do
      allow(email_account).to receive(:imap_settings).and_return(mock_settings)
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)
    end

    context 'with valid account' do
      it 'creates connection, authenticates, selects inbox, and cleans up' do
        expect(Net::IMAP).to receive(:new).with('imap.test.com', port: 993, ssl: true)
        expect(mock_imap).to receive(:login).with('test@test.com', 'password123')
        expect(mock_imap).to receive(:select).with("INBOX")
        expect(mock_imap).to receive(:logout)
        expect(mock_imap).to receive(:disconnect)

        result = service.with_connection { |imap| "success" }

        expect(result).to eq("success")
      end

      it 'yields the imap connection to the block' do
        yielded_imap = nil
        service.with_connection { |imap| yielded_imap = imap }

        expect(yielded_imap).to eq(mock_imap)
      end
    end

    context 'with inactive account' do
      before { email_account.update(active: false) }

      it 'raises ConnectionError for inactive account' do
        expect {
          service.with_connection { |imap| "should not reach" }
        }.to raise_error(ImapConnectionService::ConnectionError, "Email account is not active")
      end
    end

    context 'with missing password' do
      before { allow(email_account).to receive(:encrypted_password).and_return(nil) }

      it 'raises ConnectionError for missing password' do
        expect {
          service.with_connection { |imap| "should not reach" }
        }.to raise_error(ImapConnectionService::ConnectionError, "Email account missing password")
      end
    end

    context 'when authentication fails' do
      before do
        # Create a proper IMAP response data structure
        error_data = double('error_data', 
          data: double('data', text: 'Authentication failed'),
          text: 'Authentication failed'
        )
        allow(mock_imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new(error_data))
      end

      it 'raises AuthenticationError and cleans up connection' do
        expect(mock_imap).to receive(:logout).and_raise(Net::IMAP::Error) # Simulate logout error
        expect(mock_imap).to receive(:disconnect)

        expect {
          service.with_connection { |imap| "should not reach" }
        }.to raise_error(ImapConnectionService::AuthenticationError, /Authentication failed/)
      end
    end

    context 'when IMAP error occurs' do
      before do
        allow(mock_imap).to receive(:select).and_raise(Net::IMAP::Error, "Server error")
      end

      it 'raises ConnectionError and cleans up connection' do
        expect(mock_imap).to receive(:logout)
        expect(mock_imap).to receive(:disconnect)

        expect {
          service.with_connection { |imap| "should not reach" }
        }.to raise_error(ImapConnectionService::ConnectionError, "IMAP error: Server error")
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(mock_imap).to receive(:select).and_raise(StandardError, "Unexpected error")
      end

      it 'raises ConnectionError and cleans up connection' do
        expect(mock_imap).to receive(:logout)
        expect(mock_imap).to receive(:disconnect)

        expect {
          service.with_connection { |imap| "should not reach" }
        }.to raise_error(ImapConnectionService::ConnectionError, "Unexpected error: Unexpected error")
      end
    end

    context 'when cleanup fails' do
      before do
        allow(mock_imap).to receive(:logout).and_raise(Net::IMAP::Error, "Logout failed")
        allow(mock_imap).to receive(:disconnect).and_raise(StandardError, "Disconnect failed")
      end

      it 'silently handles cleanup failures' do
        expect {
          result = service.with_connection { |imap| "success" }
          expect(result).to eq("success")
        }.not_to raise_error
      end
    end
  end

  describe 'error handling' do
    describe 'ConnectionError' do
      it 'is a StandardError subclass' do
        expect(ImapConnectionService::ConnectionError.new).to be_a(StandardError)
      end
    end

    describe 'AuthenticationError' do
      it 'is a StandardError subclass' do
        expect(ImapConnectionService::AuthenticationError.new).to be_a(StandardError)
      end
    end

    describe 'SearchError' do
      it 'is a StandardError subclass' do
        expect(ImapConnectionService::SearchError.new).to be_a(StandardError)
      end
    end
  end

  describe 'private methods' do
    describe '#add_error' do
      it 'adds error to errors array and logs to Rails logger' do
        expect(Rails.logger).to receive(:error).with("[ImapConnectionService] #{email_account.email}: Test error")

        service.send(:add_error, "Test error")

        expect(service.errors).to include("Test error")
      end
    end
  end
end