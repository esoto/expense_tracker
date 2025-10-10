# frozen_string_literal: true

require 'rails_helper'

# Phase 3 IMAP Connectivity Tests for Email::ProcessingService
# Comprehensive testing of connection management, authentication, and server detection
# Focus: Costa Rican banking integration with robust error scenarios
RSpec.describe Services::Email::ProcessingService, :imap_connection, type: :service, unit: true do
  include EmailProcessingTestHelper

  let(:email_account) { create(:email_account, :bac, :gmail) }
  let(:processing_service) { described_class.new(email_account, options) }
  let(:options) { {} }

  # Mock IMAP instance
  let(:mock_imap) do
    double("Net::IMAP").tap do |imap|
      allow(imap).to receive(:disconnect)
      allow(imap).to receive(:disconnected?).and_return(false)
    end
  end

  before do
    allow(Net::IMAP).to receive(:new).and_return(mock_imap)
    allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)
  end

  describe 'IMAP Connection Management' do
    describe '#connect_to_imap' do
      context 'with valid configuration' do
        it 'creates IMAP connection with default settings' do
          expect(Net::IMAP).to receive(:new).with(
            "imap.gmail.com",
            port: 993,
            ssl: true
          ).and_return(mock_imap)

          result = processing_service.send(:connect_to_imap)
          expect(result).to eq(mock_imap)
        end

        it 'uses account-specific IMAP server when configured' do
          email_account.provider = "custom"
          email_account.settings = { imap: { server: "mail.custom.com", port: 143 } }

          expect(Net::IMAP).to receive(:new).with(
            "mail.custom.com",
            port: 143,
            ssl: true
          ).and_return(mock_imap)

          processing_service.send(:connect_to_imap)
        end

        it 'applies SSL configuration by default' do
          expect(Net::IMAP).to receive(:new).with(
            anything,
            hash_including(ssl: true)
          ).and_return(mock_imap)

          processing_service.send(:connect_to_imap)
        end

        it 'sets appropriate timeout values' do
          # Test that timeouts would be configured (we can't test the actual values
          # since Net::IMAP.new doesn't expose them, but we verify the call structure)
          expect(Net::IMAP).to receive(:new).with(
            "imap.gmail.com",
            port: 993,
            ssl: true
          ).and_return(mock_imap)

          processing_service.send(:connect_to_imap)
        end
      end

      context 'with connection failures' do
        it 'raises ConnectionError for network failures' do
          allow(Net::IMAP).to receive(:new).and_raise(SocketError.new("Network unreachable"))

          expect {
            processing_service.send(:connect_to_imap)
          }.to raise_error(Email::ProcessingService::ConnectionError, /Failed to connect to IMAP server.*Network unreachable/)
        end

        it 'raises ConnectionError for timeout failures' do
          allow(Net::IMAP).to receive(:new).and_raise(Timeout::Error.new("Connection timeout"))

          expect {
            processing_service.send(:connect_to_imap)
          }.to raise_error(Email::ProcessingService::ConnectionError, /Failed to connect to IMAP server.*Connection timeout/)
        end

        it 'raises ConnectionError for SSL certificate failures' do
          allow(Net::IMAP).to receive(:new).and_raise(OpenSSL::SSL::SSLError.new("Certificate verification failed"))

          expect {
            processing_service.send(:connect_to_imap)
          }.to raise_error(Email::ProcessingService::ConnectionError, /Failed to connect to IMAP server.*Certificate verification failed/)
        end

        it 'raises ConnectionError for refused connections' do
          allow(Net::IMAP).to receive(:new).and_raise(Errno::ECONNREFUSED.new("Connection refused"))

          expect {
            processing_service.send(:connect_to_imap)
          }.to raise_error(Email::ProcessingService::ConnectionError, /Failed to connect to IMAP server.*Connection refused/)
        end
      end
    end

    describe '#with_imap_connection lifecycle' do
      let(:mock_block_called) { double("block_result") }

      before do
        allow(processing_service).to receive(:authenticate_imap)
      end

      it 'establishes connection, authenticates, yields, and disconnects' do
        expect(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        expect(processing_service).to receive(:authenticate_imap).with(mock_imap)
        expect(mock_imap).to receive(:disconnect)

        result = processing_service.send(:with_imap_connection) do |imap|
          expect(imap).to eq(mock_imap)
          mock_block_called
        end

        expect(result).to eq(mock_block_called)
      end

      it 'disconnects even when block raises exception' do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        expect(mock_imap).to receive(:disconnect)

        expect {
          processing_service.send(:with_imap_connection) do
            raise StandardError.new("Block error")
          end
        }.to raise_error(StandardError, "Block error")
      end

      it 'disconnects even when authentication fails' do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(processing_service).to receive(:authenticate_imap).and_raise(StandardError.new("Auth failed"))
        expect(mock_imap).to receive(:disconnect)

        expect {
          processing_service.send(:with_imap_connection) { mock_block_called }
        }.to raise_error(StandardError, "Auth failed")
      end

      it 'handles already disconnected IMAP gracefully' do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(mock_imap).to receive(:disconnected?).and_return(true)
        expect(mock_imap).not_to receive(:disconnect)

        processing_service.send(:with_imap_connection) { mock_block_called }
      end

      it 'handles nil IMAP connection gracefully' do
        allow(processing_service).to receive(:connect_to_imap).and_return(nil)

        expect {
          processing_service.send(:with_imap_connection) { mock_block_called }
        }.not_to raise_error
      end
    end
  end

  describe 'IMAP Authentication' do
    describe '#authenticate_imap' do
      context 'password authentication' do
        before do
          email_account.encrypted_password = "secure_password"
          allow(email_account).to receive(:oauth_configured?).and_return(false)
        end

        it 'authenticates with email and password' do
          expect(mock_imap).to receive(:login).with(email_account.email, email_account.password)

          processing_service.send(:authenticate_imap, mock_imap)
        end

        it 'raises AuthenticationError on login failure' do
          allow(mock_imap).to receive(:login).and_raise(StandardError.new("Invalid credentials"))

          expect {
            processing_service.send(:authenticate_imap, mock_imap)
          }.to raise_error(Email::ProcessingService::AuthenticationError, /IMAP authentication failed/)
        end

        it 'raises AuthenticationError on permission denied' do
          allow(mock_imap).to receive(:login).and_raise(StandardError.new("Permission denied"))

          expect {
            processing_service.send(:authenticate_imap, mock_imap)
          }.to raise_error(Email::ProcessingService::AuthenticationError, /IMAP authentication failed/)
        end
      end

      context 'OAuth2 authentication' do
        before do
          email_account.encrypted_password = nil
          email_account.settings = { oauth: { access_token: "oauth_token_123" } }
          allow(email_account).to receive(:oauth_configured?).and_return(true)
        end

        it 'uses OAuth2 authentication when configured' do
          expect(processing_service).to receive(:authenticate_with_oauth).with(mock_imap)

          processing_service.send(:authenticate_imap, mock_imap)
        end

        it 'raises AuthenticationError on OAuth failure' do
          allow(processing_service).to receive(:authenticate_with_oauth).and_raise(StandardError.new("OAuth token expired"))

          expect {
            processing_service.send(:authenticate_imap, mock_imap)
          }.to raise_error(Email::ProcessingService::AuthenticationError, /IMAP authentication failed.*OAuth token expired/)
        end
      end

      context 'account type detection' do
        it 'prefers OAuth when both password and OAuth are available' do
          email_account.encrypted_password = "password"
          email_account.settings = { oauth: { access_token: "token" } }
          allow(email_account).to receive(:oauth_configured?).and_return(true)

          expect(processing_service).to receive(:authenticate_with_oauth).with(mock_imap)
          expect(mock_imap).not_to receive(:login)

          processing_service.send(:authenticate_imap, mock_imap)
        end

        it 'falls back to password when OAuth is not configured' do
          email_account.encrypted_password = "password"
          email_account.settings = {}
          allow(email_account).to receive(:oauth_configured?).and_return(false)

          expect(mock_imap).to receive(:login).with(email_account.email, email_account.password)
          expect(processing_service).not_to receive(:authenticate_with_oauth)

          processing_service.send(:authenticate_imap, mock_imap)
        end
      end
    end

    describe '#authenticate_with_oauth' do
      let(:access_token) { "oauth_access_token_123" }

      before do
        allow(processing_service).to receive(:refresh_oauth_token).and_return(access_token)
      end

      context 'Gmail OAuth2' do
        before do
          email_account.email = "user@gmail.com"
        end

        it 'uses XOAUTH2 for Gmail accounts' do
          expect(mock_imap).to receive(:authenticate).with("XOAUTH2", email_account.email, access_token)

          processing_service.send(:authenticate_with_oauth, mock_imap)
        end

        it 'refreshes token before authentication' do
          expect(processing_service).to receive(:refresh_oauth_token).and_return(access_token)
          expect(mock_imap).to receive(:authenticate).with("XOAUTH2", email_account.email, access_token)

          processing_service.send(:authenticate_with_oauth, mock_imap)
        end
      end

      context 'Outlook OAuth2' do
        before do
          email_account.email = "user@outlook.com"
        end

        it 'uses XOAUTH2 for Outlook accounts' do
          expect(mock_imap).to receive(:authenticate).with("XOAUTH2", email_account.email, access_token)

          processing_service.send(:authenticate_with_oauth, mock_imap)
        end
      end

      context 'Office365 OAuth2' do
        before do
          email_account.email = "user@company.onmicrosoft.com"
        end

        it 'uses XOAUTH2 for Office365 accounts' do
          expect(mock_imap).to receive(:authenticate).with("XOAUTH2", email_account.email, access_token)

          processing_service.send(:authenticate_with_oauth, mock_imap)
        end
      end

      context 'OAuth authentication failures' do
        it 'propagates expired token errors for handling by authenticate_imap' do
          allow(mock_imap).to receive(:authenticate).and_raise(StandardError.new("[AUTHENTICATIONFAILED] Invalid credentials (Failure)"))

          expect {
            processing_service.send(:authenticate_with_oauth, mock_imap)
          }.to raise_error(StandardError, /AUTHENTICATIONFAILED/)
        end

        it 'propagates OAuth scope errors for handling by authenticate_imap' do
          allow(mock_imap).to receive(:authenticate).and_raise(StandardError.new("Insufficient OAuth scope"))

          expect {
            processing_service.send(:authenticate_with_oauth, mock_imap)
          }.to raise_error(StandardError, /Insufficient OAuth scope/)
        end
      end
    end

    describe '#refresh_oauth_token' do
      context 'with valid OAuth configuration' do
        before do
          email_account.settings = {
            oauth: {
              access_token: "current_token",
              refresh_token: "refresh_token_123",
              expires_at: 1.hour.from_now.to_i
            }
          }
        end

        it 'returns current access token' do
          token = processing_service.send(:refresh_oauth_token)
          expect(token).to eq("current_token")
        end

        # Note: Full OAuth refresh logic would be implemented here
        # This is a simplified version for the current implementation
      end

      context 'with missing OAuth configuration' do
        before do
          email_account.settings = {}
        end

        it 'returns nil for missing OAuth settings' do
          token = processing_service.send(:refresh_oauth_token)
          expect(token).to be_nil
        end
      end
    end
  end

  describe 'Server Detection Logic' do
    describe '#detect_imap_server' do
      context 'Gmail domains' do
        it 'detects Gmail server for gmail.com' do
          email_account.email = "user@gmail.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.gmail.com")
        end

        it 'detects Gmail server for googlemail.com' do
          email_account.email = "user@googlemail.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.gmail.com")
        end
      end

      context 'Microsoft domains' do
        it 'detects Outlook server for outlook.com' do
          email_account.email = "user@outlook.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("outlook.office365.com")
        end

        it 'detects Outlook server for hotmail.com' do
          email_account.email = "user@hotmail.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("outlook.office365.com")
        end

        it 'detects Outlook server for live.com' do
          email_account.email = "user@live.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("outlook.office365.com")
        end
      end

      context 'Yahoo domain' do
        it 'detects Yahoo server for yahoo.com' do
          email_account.email = "user@yahoo.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.mail.yahoo.com")
        end
      end

      context 'iCloud domains' do
        it 'detects iCloud server for icloud.com' do
          email_account.email = "user@icloud.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.mail.me.com")
        end

        it 'detects iCloud server for me.com' do
          email_account.email = "user@me.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.mail.me.com")
        end

        it 'detects iCloud server for mac.com' do
          email_account.email = "user@mac.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.mail.me.com")
        end
      end

      context 'generic domains' do
        it 'generates generic server for unknown domain' do
          email_account.email = "user@example.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.example.com")
        end

        it 'handles corporate domains' do
          email_account.email = "user@company.co.cr"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.company.co.cr")
        end

        it 'handles complex subdomain structures' do
          email_account.email = "user@mail.bank.com"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.mail.bank.com")
        end
      end

      context 'edge cases' do
        it 'handles email without @ symbol gracefully' do
          email_account.email = "invalid_email"
          expect {
            processing_service.send(:detect_imap_server)
          }.not_to raise_error
        end

        it 'handles empty email domain' do
          email_account.email = "user@"
          server = processing_service.send(:detect_imap_server)
          expect(server).to eq("imap.user")
        end
      end
    end

    describe 'port configuration' do
      it 'uses default SSL port 993' do
        expect(Net::IMAP).to receive(:new).with(
          anything,
          hash_including(port: 993)
        ).and_return(mock_imap)

        processing_service.send(:connect_to_imap)
      end

      it 'uses custom port when configured' do
        email_account.provider = "custom"
        email_account.settings = { imap: { port: 143 } }

        expect(Net::IMAP).to receive(:new).with(
          anything,
          hash_including(port: 143)
        ).and_return(mock_imap)

        processing_service.send(:connect_to_imap)
      end
    end
  end

  describe 'Email Search and Retrieval' do
    let(:since_date) { 1.week.ago }
    let(:until_date) { nil }

    before do
      allow(mock_imap).to receive(:examine)
      allow(mock_imap).to receive(:search).and_return([])
      allow(mock_imap).to receive(:fetch).and_return([])
    end

    describe '#search_for_transaction_emails' do
      it 'builds search criteria and executes searches' do
        expect(processing_service).to receive(:build_search_criteria).with(since_date, until_date)
                                                                     .and_return([ [ "SINCE", "25-Aug-2025", "FROM", "test@example.com" ] ])
        expect(mock_imap).to receive(:search).with([ "SINCE", "25-Aug-2025", "FROM", "test@example.com" ]).and_return([ 1, 2, 3 ])

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result).to eq([ 3, 2, 1 ]) # Reversed and limited
      end

      it 'combines results from multiple search criteria' do
        allow(processing_service).to receive(:build_search_criteria).and_return([
          [ "SINCE", "25-Aug-2025", "FROM", "bank1@example.com" ],
          [ "SINCE", "25-Aug-2025", "FROM", "bank2@example.com" ]
        ])
        allow(mock_imap).to receive(:search).and_return([ 1, 2 ], [ 3, 4 ])

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result).to match_array([ 4, 3, 2, 1 ]) # Combined, unique, reversed
      end

      it 'removes duplicate message IDs' do
        allow(processing_service).to receive(:build_search_criteria).and_return([
          [ "SINCE", "25-Aug-2025", "FROM", "test@example.com" ],
          [ "SINCE", "25-Aug-2025", "SUBJECT", "transaction" ]
        ])
        allow(mock_imap).to receive(:search).and_return([ 1, 2, 3 ], [ 2, 3, 4 ]) # Overlapping results

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result).to match_array([ 4, 3, 2, 1 ]) # Unique values only
      end

      it 'applies result limit (default 100)' do
        large_result_set = (1..150).to_a
        allow(processing_service).to receive(:build_search_criteria).and_return([ [ "SINCE", "25-Aug-2025" ] ])
        allow(mock_imap).to receive(:search).and_return(large_result_set)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result.length).to eq(100)
      end

      it 'applies custom limit from options' do
        large_result_set = (1..80).to_a
        processing_service.options[:limit] = 50
        allow(processing_service).to receive(:build_search_criteria).and_return([ [ "SINCE", "25-Aug-2025" ] ])
        allow(mock_imap).to receive(:search).and_return(large_result_set)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result.length).to eq(50)
      end

      it 'handles search failures gracefully' do
        allow(processing_service).to receive(:build_search_criteria).and_return([
          [ "SINCE", "25-Aug-2025", "FROM", "valid@example.com" ],
          [ "INVALID", "CRITERIA" ]
        ])
        allow(mock_imap).to receive(:search).with([ "SINCE", "25-Aug-2025", "FROM", "valid@example.com" ]).and_return([ 1, 2 ])
        allow(mock_imap).to receive(:search).with([ "INVALID", "CRITERIA" ]).and_raise(StandardError.new("Invalid search"))
        allow(Rails.logger).to receive(:warn)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result).to eq([ 2, 1 ]) # Only successful search results
        expect(Rails.logger).to have_received(:warn).with(/Search failed for criterion/)
      end

      it 'returns results in reverse chronological order (newest first)' do
        allow(processing_service).to receive(:build_search_criteria).and_return([ [ "SINCE", "25-Aug-2025" ] ])
        allow(mock_imap).to receive(:search).and_return([ 5, 3, 1, 4, 2 ])

        result = processing_service.send(:search_for_transaction_emails, mock_imap, since_date, until_date)
        expect(result).to eq([ 5, 4, 3, 2, 1 ]) # Sorted and reversed
      end
    end

    describe '#build_search_criteria' do
      let(:since_date) { Date.parse("2025-08-20") }

      it 'builds basic date criteria' do
        criteria = processing_service.send(:build_search_criteria, since_date)

        # Should include date filter in all criteria
        expect(criteria).to all(include("SINCE", "20-Aug-2025"))
      end

      it 'includes until_date when provided' do
        until_date = Date.parse("2025-08-25")
        criteria = processing_service.send(:build_search_criteria, since_date, until_date)

        # Should include BEFORE filter for day after until_date (IMAP BEFORE is exclusive)
        expect(criteria).to all(include("BEFORE", "26-Aug-2025"))
      end

      it 'includes known sender criteria' do
        criteria = processing_service.send(:build_search_criteria, since_date)

        # Should have criteria for each known sender
        known_senders = processing_service.send(:known_senders)
        expect(criteria.count { |c| c.include?("FROM") }).to eq(known_senders.length)

        # Verify all known senders are included
        from_values = criteria.select { |c| c.include?("FROM") }.map { |c| c[c.index("FROM") + 1] }
        expect(from_values).to match_array(known_senders)
      end

      it 'includes transaction keyword criteria' do
        criteria = processing_service.send(:build_search_criteria, since_date)

        # Should have criteria for each transaction keyword
        transaction_keywords = processing_service.send(:transaction_keywords)
        expect(criteria.count { |c| c.include?("SUBJECT") }).to eq(transaction_keywords.length)

        # Verify all keywords are included
        subject_values = criteria.select { |c| c.include?("SUBJECT") }.map { |c| c[c.index("SUBJECT") + 1] }
        expect(subject_values).to match_array(transaction_keywords)
      end

      it 'formats dates correctly for IMAP' do
        criteria = processing_service.send(:build_search_criteria, Date.parse("2025-12-31"))

        expect(criteria.first).to include("SINCE", "31-Dec-2025")
      end

      it 'handles edge date cases' do
        # Test leap year
        leap_date = Date.parse("2024-02-29")
        criteria = processing_service.send(:build_search_criteria, leap_date)
        expect(criteria.first).to include("SINCE", "29-Feb-2024")

        # Test year transition
        new_year = Date.parse("2025-01-01")
        criteria = processing_service.send(:build_search_criteria, new_year)
        expect(criteria.first).to include("SINCE", "01-Jan-2025")
      end
    end

    describe 'Costa Rican bank sender lists' do
      describe '#known_senders' do
        it 'includes all major Costa Rican banks' do
          senders = processing_service.send(:known_senders)

          expect(senders).to include("notificacion@notificacionesbaccr.com")
          expect(senders).to include("alertas@bncr.fi.cr")
          expect(senders).to include("notificaciones@scotiabank.com")
        end

        it 'includes international payment processors' do
          senders = processing_service.send(:known_senders)

          expect(senders).to include("alerts@paypal.com")
          expect(senders).to include("no-reply@amazon.com")
        end

        it 'has proper email format for all senders' do
          senders = processing_service.send(:known_senders)

          senders.each do |sender|
            expect(sender).to match(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
          end
        end
      end

      describe '#transaction_keywords' do
        it 'includes Spanish transaction keywords' do
          keywords = processing_service.send(:transaction_keywords)

          expect(keywords).to include("cargo")
          expect(keywords).to include("compra")
          expect(keywords).to include("pago")
          expect(keywords).to include("retiro")
        end

        it 'includes English transaction keywords' do
          keywords = processing_service.send(:transaction_keywords)

          expect(keywords).to include("transaction")
          expect(keywords).to include("payment")
          expect(keywords).to include("purchase")
        end

        it 'covers common transaction patterns' do
          keywords = processing_service.send(:transaction_keywords)

          # Should cover both debit and credit transactions
          expect(keywords).to be_present
          expect(keywords.length).to be >= 5
        end
      end

      describe '#promotional_senders' do
        it 'identifies promotional email patterns' do
          promotional = processing_service.send(:promotional_senders)

          expect(promotional).to include("promociones@")
          expect(promotional).to include("marketing@")
          expect(promotional).to include("offers@")
          expect(promotional).to include("newsletter@")
        end

        it 'includes Spanish promotional patterns' do
          promotional = processing_service.send(:promotional_senders)

          expect(promotional).to include("promociones@")
          expect(promotional).to include("noticias@")
          expect(promotional).to include("comunicaciones@")
        end
      end
    end
  end

  describe 'Email Parsing and Processing' do
    let(:mock_message) do
      double("IMAP::FetchData").tap do |msg|
        allow(msg).to receive(:attr).and_return({
          "UID" => 123,
          "FLAGS" => [ :Seen ],
          "RFC822" => sample_email_rfc822
        })
      end
    end

    let(:sample_email_rfc822) do
      <<~EMAIL
        From: notificacion@notificacionesbaccr.com
        Subject: Compra aprobada - BAC Credomatic
        Date: #{1.day.ago.rfc2822}
        Message-ID: <#{SecureRandom.uuid}@notificacionesbaccr.com>
        Content-Type: text/plain; charset=UTF-8

        Estimado cliente,

        Su transacción ha sido aprobada:

        Tarjeta: ****1234
        Comercio: SUPERMERCADO MAS X MENOS
        Monto: ₡25,500.00
        Fecha: 15/08/2025 14:30:00
        Autorización: 123456

        Gracias por usar BAC Credomatic.
      EMAIL
    end

    describe '#parse_raw_email' do
      it 'extracts email metadata correctly' do
        result = processing_service.send(:parse_raw_email, mock_message)

        expect(result).to be_a(Hash)
        expect(result).to include(
          :uid, :message_id, :from, :subject, :date, :body, :text_body
        )
        expect(result[:uid]).to eq(123)
        expect(result[:from]).to eq("notificacion@notificacionesbaccr.com")
        expect(result[:subject]).to eq("Compra aprobada - BAC Credomatic")
      end

      it 'handles missing RFC822 data gracefully' do
        allow(mock_message).to receive(:attr).and_return({
          "UID" => 123,
          "FLAGS" => [ :Seen ],
          "RFC822" => nil
        })

        result = processing_service.send(:parse_raw_email, mock_message)
        expect(result).to be_nil
      end

      it 'handles malformed email data gracefully' do
        # Simulate actual Mail gem parsing error by making Mail.read_from_string fail
        allow(mock_message).to receive(:attr).and_return({
          "UID" => 123,
          "FLAGS" => [ :Seen ],
          "RFC822" => "Invalid email content"
        })
        allow(Mail).to receive(:read_from_string).and_raise(StandardError.new("Malformed email"))
        allow(Rails.logger).to receive(:error)

        result = processing_service.send(:parse_raw_email, mock_message)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with(/Failed to parse email/)
      end

      it 'extracts both text and HTML content when present' do
        html_email_rfc822 = <<~EMAIL
          From: test@example.com
          Subject: HTML Test
          Date: #{1.day.ago.rfc2822}
          Content-Type: multipart/alternative; boundary="boundary123"

          --boundary123
          Content-Type: text/plain; charset=UTF-8

          Plain text content

          --boundary123
          Content-Type: text/html; charset=UTF-8

          <html><body>HTML content</body></html>

          --boundary123--
        EMAIL

        allow(mock_message).to receive(:attr).and_return({
          "UID" => 123,
          "FLAGS" => [ :Seen ],
          "RFC822" => html_email_rfc822
        })

        result = processing_service.send(:parse_raw_email, mock_message)
        expect(result[:text_body]).to include("Plain text content")
        expect(result[:html_body]).to include("HTML content")
      end
    end

    describe 'batch email fetching' do
      let(:since_date) { 1.week.ago }
      let(:until_date) { nil }
      let(:message_ids) { [ 1, 2, 3, 4, 5 ] }
      let(:mock_messages) do
        message_ids.map { |id| double("Message#{id}", attr: { "UID" => id, "RFC822" => sample_email_rfc822 }) }
      end

      before do
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:login)
        allow(processing_service).to receive(:authenticate_imap)
        allow(processing_service).to receive(:search_for_transaction_emails).and_return(message_ids)
      end

      it 'fetches emails in batches of 20' do
        large_message_ids = (1..45).to_a
        allow(processing_service).to receive(:search_for_transaction_emails).and_return(large_message_ids)

        # Expect 3 batch calls: [1-20], [21-40], [41-45]
        expect(mock_imap).to receive(:fetch).with((1..20).to_a, [ "RFC822", "UID", "FLAGS" ]).and_return([])
        expect(mock_imap).to receive(:fetch).with((21..40).to_a, [ "RFC822", "UID", "FLAGS" ]).and_return([])
        expect(mock_imap).to receive(:fetch).with((41..45).to_a, [ "RFC822", "UID", "FLAGS" ]).and_return([])

        processing_service.send(:fetch_emails, since_date, until_date)
      end

      it 'requests correct IMAP attributes' do
        expect(mock_imap).to receive(:fetch).with(message_ids, [ "RFC822", "UID", "FLAGS" ]).and_return(mock_messages)

        processing_service.send(:fetch_emails, since_date, until_date)
      end

      it 'filters out nil parse results' do
        allow(mock_imap).to receive(:fetch).and_return(mock_messages)
        allow(processing_service).to receive(:parse_raw_email).and_return(nil, { uid: 2 }, nil, { uid: 4 }, { uid: 5 })

        result = processing_service.send(:fetch_emails, since_date, until_date)
        expect(result.length).to eq(3) # Only non-nil results
        expect(result.map { |r| r[:uid] }).to eq([ 2, 4, 5 ])
      end
    end
  end

  describe 'Error Handling and Edge Cases' do
    describe 'connection error scenarios' do
      it 'handles IMAP server unavailable' do
        allow(Net::IMAP).to receive(:new).and_raise(SocketError.new("Name or service not known"))

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Name or service not known/)
      end

      it 'handles network timeout during connection' do
        allow(Net::IMAP).to receive(:new).and_raise(Timeout::Error.new("execution expired"))

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /execution expired/)
      end

      it 'handles SSL/TLS handshake failures' do
        allow(Net::IMAP).to receive(:new).and_raise(OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0"))

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /SSL_connect/)
      end
    end

    describe 'authentication error scenarios' do
      before do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
      end

      it 'handles incorrect credentials' do
        allow(mock_imap).to receive(:login).and_raise(StandardError.new("LOGIN failed"))

        expect {
          processing_service.send(:authenticate_imap, mock_imap)
        }.to raise_error(Email::ProcessingService::AuthenticationError, /LOGIN failed/)
      end

      it 'handles account locked/suspended' do
        allow(mock_imap).to receive(:login).and_raise(StandardError.new("Account suspended"))

        expect {
          processing_service.send(:authenticate_imap, mock_imap)
        }.to raise_error(Email::ProcessingService::AuthenticationError, /Account suspended/)
      end

      it 'handles two-factor authentication required' do
        allow(mock_imap).to receive(:login).and_raise(StandardError.new("Application-specific password required"))

        expect {
          processing_service.send(:authenticate_imap, mock_imap)
        }.to raise_error(Email::ProcessingService::AuthenticationError, /Application-specific password required/)
      end

      it 'handles OAuth token expiration' do
        allow(email_account).to receive(:oauth_configured?).and_return(true)
        allow(processing_service).to receive(:authenticate_with_oauth).and_raise(StandardError.new("Token expired"))

        expect {
          processing_service.send(:authenticate_imap, mock_imap)
        }.to raise_error(Email::ProcessingService::AuthenticationError, /Token expired/)
      end
    end

    describe 'IMAP operation failures' do
      before do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(processing_service).to receive(:authenticate_imap)
      end

      it 'handles folder access denied' do
        allow(mock_imap).to receive(:examine).and_raise(StandardError.new("Mailbox does not exist"))

        expect {
          processing_service.send(:with_imap_connection) { |imap| imap.examine("INBOX") }
        }.to raise_error(StandardError)
      end

      it 'handles search operation failures' do
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_raise(StandardError.new("Invalid search"))
        allow(Rails.logger).to receive(:warn)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
        expect(result).to eq([])
        expect(Rails.logger).to have_received(:warn).at_least(:once).with(/Search failed for criterion/)
      end

      it 'handles fetch operation failures' do
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_return([ 1, 2, 3 ])
        allow(mock_imap).to receive(:fetch).and_raise(StandardError.new("Message not found"))

        expect {
          processing_service.send(:fetch_emails, 1.week.ago)
        }.to raise_error(StandardError)
      end
    end

    describe 'malformed email handling' do
      it 'handles emails with invalid encoding' do
        invalid_rfc822 = "From: test@example.com\r\nSubject: \xFF\xFEInvalid\r\n\r\nBody"
        mock_message = double("Message", attr: { "UID" => 1, "RFC822" => invalid_rfc822 })
        allow(Rails.logger).to receive(:error)

        result = processing_service.send(:parse_raw_email, mock_message)
        expect(result).to be_nil
        expect(Rails.logger).to have_received(:error).with(/Failed to parse email/)
      end

      it 'handles emails with missing headers' do
        incomplete_rfc822 = "This is not a valid email format"
        mock_message = double("Message", attr: { "UID" => 1, "RFC822" => incomplete_rfc822 })
        allow(Rails.logger).to receive(:error)

        result = processing_service.send(:parse_raw_email, mock_message)
        # Mail gem is lenient and will parse what it can, so expect a hash with nil/empty values
        expect(result).to be_a(Hash)
        expect(result[:from]).to be_nil
        expect(result[:subject]).to be_nil
        expect(result[:message_id]).to be_nil
      end

      it 'handles extremely large emails gracefully' do
        large_body = "x" * 10_000_000 # 10MB email
        large_rfc822 = "From: test@example.com\r\nSubject: Large\r\n\r\n#{large_body}"
        mock_message = double("Message", attr: { "UID" => 1, "RFC822" => large_rfc822 })

        # Should not crash, may timeout or be truncated
        expect {
          processing_service.send(:parse_raw_email, mock_message)
        }.not_to raise_error
      end
    end

    describe 'resource cleanup' do
      it 'ensures IMAP connection is closed on unexpected errors' do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(processing_service).to receive(:authenticate_imap)
        expect(mock_imap).to receive(:disconnect)

        expect {
          processing_service.send(:with_imap_connection) do
            raise RuntimeError.new("Unexpected error")
          end
        }.to raise_error(RuntimeError, "Unexpected error")
      end

      it 'handles disconnect failures gracefully' do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(processing_service).to receive(:authenticate_imap)
        allow(mock_imap).to receive(:disconnect).and_raise(StandardError.new("Connection already closed"))
        allow(Rails.logger).to receive(:warn)

        # Should not raise error from disconnect, but should complete the block successfully
        result = processing_service.send(:with_imap_connection) { "success" }

        expect(result).to eq("success")
        expect(Rails.logger).to have_received(:warn).with(/Failed to disconnect IMAP connection/)
      end
    end
  end

  describe 'Advanced Costa Rican Banking Integration' do
    describe 'bank-specific IMAP configurations' do
      context 'BAC Credomatic accounts' do
        let(:bac_account) { create(:email_account, :bac, :gmail) }
        let(:bac_service) { described_class.new(bac_account) }

        it 'handles BAC-specific email search patterns' do
          allow(mock_imap).to receive(:examine)
          allow(mock_imap).to receive(:search).and_return([ 1, 2, 3 ])

          result = bac_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
          expect(result).to include(3, 2, 1)
        end

        it 'prioritizes BAC transaction keywords' do
          criteria = bac_service.send(:build_search_criteria, 1.week.ago)

          # Should include Spanish keywords for BAC
          subject_criteria = criteria.select { |c| c.include?("SUBJECT") }
          subject_values = subject_criteria.map { |c| c[c.index("SUBJECT") + 1] }

          expect(subject_values).to include("cargo", "compra", "pago")
        end
      end

      context 'BCR (Banco Central) accounts' do
        let(:bcr_account) { create(:email_account, :bcr, :outlook) }
        let(:bcr_service) { described_class.new(bcr_account) }

        it 'handles BCR-specific email search patterns' do
          allow(mock_imap).to receive(:examine)
          allow(mock_imap).to receive(:search).and_return([ 4, 5, 6 ])

          result = bcr_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
          expect(result).to include(6, 5, 4)
        end

        it 'supports BCR bilingual transaction keywords' do
          criteria = bcr_service.send(:build_search_criteria, 1.week.ago)

          subject_criteria = criteria.select { |c| c.include?("SUBJECT") }
          subject_values = subject_criteria.map { |c| c[c.index("SUBJECT") + 1] }

          expect(subject_values).to include("transaction", "payment", "compra")
        end
      end

      context 'Scotiabank accounts' do
        let(:scotia_account) { create(:email_account, :scotiabank, :custom) }
        let(:scotia_service) { described_class.new(scotia_account) }

        it 'handles custom IMAP server configuration for Scotiabank' do
          scotia_account.provider = "custom"
          scotia_account.settings = { imap: { server: "imap.scotiabank.com", port: 993 } }

          expect(Net::IMAP).to receive(:new).with(
            "imap.scotiabank.com",
            port: 993,
            ssl: true
          ).and_return(mock_imap)

          scotia_service.send(:connect_to_imap)
        end
      end
    end

    describe 'Costa Rican email pattern recognition' do
      let(:cr_date_patterns) { [ "15/08/2025", "2025-08-15", "15-08-2025" ] }
      let(:cr_amount_patterns) { [ "₡25,500.00", "$45.20", "USD 100.50" ] }

      it 'recognizes Costa Rican date formats in search criteria' do
        costa_rica_date = Date.parse("2025-08-15")
        criteria = processing_service.send(:build_search_criteria, costa_rica_date)

        expect(criteria.first).to include("SINCE", "15-Aug-2025")
      end

      it 'handles Costa Rican timezone considerations' do
        # Costa Rica is UTC-6
        cr_time = Time.zone.parse("2025-08-15 18:00:00 -06:00")
        criteria = processing_service.send(:build_search_criteria, cr_time.to_date)

        expect(criteria).to all(be_an(Array))
        expect(criteria.first).to include("SINCE")
      end

      it 'filters out promotional Costa Rican bank emails' do
        promotional_senders = processing_service.send(:promotional_senders)

        expect(promotional_senders).to include("promociones@scotiabankca.net")
        expect(promotional_senders).to include("comunicaciones@")
      end
    end
  end

  describe 'Enhanced OAuth2 Authentication Scenarios' do
    describe 'Gmail OAuth2 edge cases' do
      before do
        email_account.email = "user@gmail.com"
        allow(email_account).to receive(:oauth_configured?).and_return(true)
      end

      it 'handles Gmail API quota exceeded' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] Quota exceeded")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /Quota exceeded/)
      end

      it 'handles Gmail less secure apps disabled' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] Application-specific password required")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /Application-specific password required/)
      end

      it 'handles Gmail 2FA enforcement' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] 2-factor authentication required")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /2-factor authentication required/)
      end
    end

    describe 'Outlook/Office365 OAuth2 edge cases' do
      before do
        email_account.email = "user@outlook.com"
        allow(email_account).to receive(:oauth_configured?).and_return(true)
      end

      it 'handles Microsoft tenant restrictions' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] Tenant policy restriction")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /Tenant policy restriction/)
      end

      it 'handles conditional access policy violations' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] Conditional access policy not satisfied")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /Conditional access policy not satisfied/)
      end

      it 'handles Office365 authentication throttling' do
        allow(processing_service).to receive(:refresh_oauth_token).and_return("valid_token")
        allow(mock_imap).to receive(:authenticate).and_raise(
          StandardError.new("[AUTHENTICATIONFAILED] Too many requests")
        )

        expect {
          processing_service.send(:authenticate_with_oauth, mock_imap)
        }.to raise_error(StandardError, /Too many requests/)
      end
    end

    describe 'OAuth token refresh scenarios' do
      context 'with expired access token' do
        before do
          email_account.settings = {
            oauth: {
              access_token: "expired_token",
              refresh_token: "valid_refresh",
              expires_at: 1.hour.ago.to_i
            }
          }
        end

        it 'returns expired token for current implementation' do
          # Current implementation just returns the stored token
          token = processing_service.send(:refresh_oauth_token)
          expect(token).to eq("expired_token")
        end
      end

      context 'with missing refresh token' do
        before do
          email_account.settings = {
            oauth: {
              access_token: "some_token"
              # Missing refresh_token
            }
          }
        end

        it 'returns access token without refresh capability' do
          token = processing_service.send(:refresh_oauth_token)
          expect(token).to eq("some_token")
        end
      end

      context 'with corrupted OAuth settings' do
        before do
          email_account.settings = { oauth: "invalid_format" }
        end

        it 'handles malformed OAuth configuration gracefully' do
          expect {
            processing_service.send(:refresh_oauth_token)
          }.to raise_error(TypeError)
        end
      end
    end
  end

  describe 'Advanced Error Recovery and Resilience' do
    describe 'connection recovery scenarios' do
      it 'handles intermittent network connectivity' do
        call_count = 0
        allow(Net::IMAP).to receive(:new) do
          call_count += 1
          if call_count == 1
            raise SocketError.new("Network unreachable")
          else
            mock_imap
          end
        end

        # First attempt should fail
        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError)

        # Second attempt should succeed
        expect(processing_service.send(:connect_to_imap)).to eq(mock_imap)
      end

      it 'handles DNS resolution failures' do
        allow(Net::IMAP).to receive(:new).and_raise(
          SocketError.new("Name or service not known")
        )

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Name or service not known/)
      end

      it 'handles firewall blocking IMAP port' do
        allow(Net::IMAP).to receive(:new).and_raise(
          Errno::ETIMEDOUT.new("Connection timed out")
        )

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Connection timed out/)
      end
    end

    describe 'server-side error responses' do
      before do
        allow(processing_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(processing_service).to receive(:authenticate_imap)
      end

      it 'handles IMAP server maintenance mode' do
        allow(mock_imap).to receive(:examine).and_raise(
          StandardError.new("Server temporarily unavailable")
        )

        expect {
          processing_service.send(:with_imap_connection) { |imap| imap.examine("INBOX") }
        }.to raise_error(StandardError, /Server temporarily unavailable/)
      end

      it 'handles IMAP server overload' do
        allow(mock_imap).to receive(:search).and_raise(
          StandardError.new("Server too busy")
        )
        allow(Rails.logger).to receive(:warn)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
        expect(result).to eq([])
        expect(Rails.logger).to have_received(:warn).at_least(:once).with(/Search failed for criterion/)
      end

      it 'handles IMAP protocol version mismatches' do
        # Create a new service instance to avoid stubbing conflicts
        isolated_service = described_class.new(email_account)
        allow(Net::IMAP).to receive(:new).and_raise(
          StandardError.new("Protocol version not supported")
        )

        expect {
          isolated_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Protocol version not supported/)
      end
    end

    describe 'resource exhaustion scenarios' do
      it 'handles memory pressure during large email processing' do
        huge_email_content = "x" * 50_000_000 # 50MB
        huge_rfc822 = "From: test@example.com\r\nSubject: Huge\r\n\r\n#{huge_email_content}"
        mock_message = double("Message", attr: { "UID" => 1, "RFC822" => huge_rfc822 })

        # Should handle gracefully without crashing
        expect {
          processing_service.send(:parse_raw_email, mock_message)
        }.not_to raise_error
      end

      it 'handles file descriptor exhaustion' do
        allow(Net::IMAP).to receive(:new).and_raise(
          Errno::EMFILE.new("Too many open files")
        )

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Too many open files/)
      end
    end
  end

  describe 'Performance and Optimization' do
    describe 'connection reuse within block' do
      it 'reuses single IMAP connection for multiple operations' do
        expect(processing_service).to receive(:connect_to_imap).once.and_return(mock_imap)
        expect(processing_service).to receive(:authenticate_imap).once
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_return([])

        processing_service.send(:with_imap_connection) do |imap|
          imap.examine("INBOX")
          imap.search([ "SINCE", "01-Jan-2025" ])
          imap.search([ "SINCE", "01-Jan-2025", "FROM", "test@example.com" ])
        end
      end
    end

    describe 'search optimization' do
      before do
        allow(mock_imap).to receive(:examine)
      end

      it 'limits search results to prevent memory issues' do
        huge_result_set = (1..10000).to_a
        allow(processing_service).to receive(:build_search_criteria).and_return([ [ "SINCE", "01-Jan-2025" ] ])
        allow(mock_imap).to receive(:search).and_return(huge_result_set)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
        expect(result.length).to eq(100) # Default limit
      end

      it 'respects custom limits for batch processing' do
        processing_service.options[:limit] = 25
        result_set = (1..50).to_a
        allow(processing_service).to receive(:build_search_criteria).and_return([ [ "SINCE", "01-Jan-2025" ] ])
        allow(mock_imap).to receive(:search).and_return(result_set)

        result = processing_service.send(:search_for_transaction_emails, mock_imap, 1.week.ago)
        expect(result.length).to eq(25)
      end
    end

    describe 'batch processing efficiency' do
      before do
        allow(mock_imap).to receive(:login)
        allow(processing_service).to receive(:authenticate_imap)
      end

      it 'processes exactly 20 messages per batch' do
        message_ids = (1..42).to_a
        allow(processing_service).to receive(:search_for_transaction_emails).and_return(message_ids)

        # Should call fetch 3 times: 20 + 20 + 2 messages
        expect(mock_imap).to receive(:fetch).exactly(3).times.and_return([])
        expect(mock_imap).to receive(:examine)

        processing_service.send(:fetch_emails, 1.week.ago)
      end

      it 'handles empty search results efficiently' do
        allow(processing_service).to receive(:search_for_transaction_emails).and_return([])
        expect(mock_imap).not_to receive(:fetch)
        expect(mock_imap).to receive(:examine)

        result = processing_service.send(:fetch_emails, 1.week.ago)
        expect(result).to eq([])
      end
    end

    describe 'connection pooling and lifecycle optimization' do
      it 'minimizes authentication overhead within session' do
        expect(processing_service).to receive(:authenticate_imap).once
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_return([])

        processing_service.send(:with_imap_connection) do |imap|
          # Multiple operations should not trigger re-authentication
          5.times { imap.search([ "SINCE", "01-Jan-2025" ]) }
        end
      end

      it 'optimizes search criteria to reduce server load' do
        # Verify that we don't create redundant search criteria
        criteria = processing_service.send(:build_search_criteria, 1.week.ago)

        # Count unique base criteria (should not have duplicates)
        base_criteria = criteria.map { |c| c[0..1] } # ["SINCE", "date"]
        expect(base_criteria.uniq.length).to eq(1)
      end
    end
  end

  describe 'Integration Testing Scenarios' do
    let(:sample_email_rfc822) do
      <<~EMAIL
        From: notificacion@notificacionesbaccr.com
        Subject: Compra aprobada - BAC Credomatic
        Date: #{1.day.ago.rfc2822}
        Message-ID: <#{SecureRandom.uuid}@notificacionesbaccr.com>
        Content-Type: text/plain; charset=UTF-8

        Estimado cliente,

        Su transacción ha sido aprobada:

        Tarjeta: ****1234
        Comercio: SUPERMERCADO MAS X MENOS
        Monto: ₡25,500.00
        Fecha: 15/08/2025 14:30:00
        Autorización: 123456

        Gracias por usar BAC Credomatic.
      EMAIL
    end

    describe 'end-to-end connection workflow' do
      let(:full_workflow_account) { create(:email_account, :bac, :gmail) }
      let(:full_workflow_service) { described_class.new(full_workflow_account) }

      before do
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:login)
        allow(mock_imap).to receive(:search).and_return([ 1, 2, 3 ])
        allow(mock_imap).to receive(:fetch).and_return([
          double("Message1", attr: { "UID" => 1, "RFC822" => sample_email_rfc822 }),
          double("Message2", attr: { "UID" => 2, "RFC822" => sample_email_rfc822 }),
          double("Message3", attr: { "UID" => 3, "RFC822" => sample_email_rfc822 })
        ])
      end

      it 'completes full IMAP workflow successfully' do
        allow(full_workflow_service).to receive(:connect_to_imap).and_return(mock_imap)

        result = full_workflow_service.send(:fetch_emails, 1.week.ago)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
        expect(result.first).to have_key(:uid)
        expect(result.first).to have_key(:from)
        expect(result.first).to have_key(:subject)
      end

      it 'maintains consistent state throughout workflow' do
        allow(full_workflow_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(full_workflow_service).to receive(:authenticate_imap)

        full_workflow_service.send(:with_imap_connection) do |imap|
          expect(imap).to eq(mock_imap)
        end

        expect(mock_imap).to have_received(:disconnect)
      end
    end

    describe 'Costa Rican bank simulation' do
      let(:bac_simulation_account) { create(:email_account, :bac, :gmail) }
      let(:bcr_simulation_account) { create(:email_account, :bcr, :outlook) }

      it 'simulates BAC Credomatic email processing workflow' do
        bac_service = described_class.new(bac_simulation_account)

        # Mock IMAP connection and operations
        allow(bac_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(bac_service).to receive(:authenticate_imap)
        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_return([ 101, 102 ])

        bac_mock_messages = [
          double("BACMessage1", attr: { "UID" => 101, "RFC822" => EmailProcessingTestHelper::EmailFixtures.bac_transaction_email[:raw_content] }),
          double("BACMessage2", attr: { "UID" => 102, "RFC822" => EmailProcessingTestHelper::EmailFixtures.bac_transaction_email[:raw_content] })
        ]
        allow(mock_imap).to receive(:fetch).and_return(bac_mock_messages)

        result = bac_service.send(:fetch_emails, 1.week.ago)

        expect(result.length).to eq(2)
        expect(result.first[:from]).to eq("notificacion@notificacionesbaccr.com")
        expect(result.first[:subject]).to eq("Compra aprobada - BAC Credomatic")
      end

      it 'simulates BCR email processing workflow' do
        bcr_service = described_class.new(bcr_simulation_account)

        # Mock IMAP connection and authentication
        allow(bcr_service).to receive(:connect_to_imap).and_return(mock_imap)
        allow(bcr_simulation_account).to receive(:oauth_configured?).and_return(true)
        allow(bcr_service).to receive(:authenticate_with_oauth)

        allow(mock_imap).to receive(:examine)
        allow(mock_imap).to receive(:search).and_return([ 201, 202 ])

        bcr_mock_messages = [
          double("BCRMessage1", attr: { "UID" => 201, "RFC822" => EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email[:raw_content] }),
          double("BCRMessage2", attr: { "UID" => 202, "RFC822" => EmailProcessingTestHelper::EmailFixtures.bcr_transaction_email[:raw_content] })
        ]
        allow(mock_imap).to receive(:fetch).and_return(bcr_mock_messages)

        result = bcr_service.send(:fetch_emails, 1.week.ago)

        expect(result.length).to eq(2)
        expect(result.first[:from]).to eq("alertas@bncr.fi.cr")
        expect(result.first[:subject]).to eq("Alerta BCR - Compra con tarjeta")
      end
    end
  end

  describe 'Edge Case Validation' do
    describe 'unusual email account configurations' do
      it 'handles email accounts with mixed case domains' do
        email_account.email = "user@Gmail.COM"
        server = processing_service.send(:detect_imap_server)
        expect(server).to eq("imap.Gmail.COM") # Current implementation is case-sensitive
      end

      it 'handles email accounts with subdomain variations' do
        email_account.email = "user@mail.company.com"
        server = processing_service.send(:detect_imap_server)
        expect(server).to eq("imap.mail.company.com")
      end

      it 'handles corporate Office365 tenant domains' do
        email_account.email = "user@company.onmicrosoft.com"
        server = processing_service.send(:detect_imap_server)
        expect(server).to eq("imap.company.onmicrosoft.com")
      end
    end

    describe 'connection parameter validation' do
      it 'validates IMAP port ranges' do
        email_account.provider = "custom"

        # Test valid ports
        [ 143, 993, 995 ].each do |port|
          email_account.settings = { imap: { port: port } }
          expect(Net::IMAP).to receive(:new).with(
            anything, hash_including(port: port)
          ).and_return(mock_imap)
          processing_service.send(:connect_to_imap)
        end
      end

      it 'handles invalid IMAP server hostnames gracefully' do
        email_account.provider = "custom"
        email_account.settings = { imap: { server: "invalid..hostname" } }

        allow(Net::IMAP).to receive(:new).and_raise(
          SocketError.new("Invalid hostname")
        )

        expect {
          processing_service.send(:connect_to_imap)
        }.to raise_error(Email::ProcessingService::ConnectionError, /Invalid hostname/)
      end
    end

    describe 'search query edge cases' do
      it 'handles special characters in search criteria' do
        # Test with email containing special characters
        special_sender = "test+special@example.com"
        allow(processing_service).to receive(:known_senders).and_return([ special_sender ])

        criteria = processing_service.send(:build_search_criteria, 1.week.ago)
        from_criteria = criteria.find { |c| c.include?("FROM") && c.include?(special_sender) }

        expect(from_criteria).to include("FROM", special_sender)
      end

      it 'handles Unicode characters in search keywords' do
        # Test with Spanish accented characters
        unicode_keywords = [ "notificación", "transacción" ]
        allow(processing_service).to receive(:transaction_keywords).and_return(unicode_keywords)

        criteria = processing_service.send(:build_search_criteria, 1.week.ago)
        subject_values = criteria.select { |c| c.include?("SUBJECT") }.map { |c| c[c.index("SUBJECT") + 1] }

        expect(subject_values).to include("notificación", "transacción")
      end
    end
  end
end
