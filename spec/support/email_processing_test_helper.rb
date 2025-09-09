# frozen_string_literal: true

# Test helper for Email::ProcessingService testing
# Provides IMAP mocking, email fixtures, and test utilities
module EmailProcessingTestHelper
  # IMAP Mock Helper
  class MockIMAP
    attr_accessor :disconnected, :authenticated, :examined_folder
    attr_reader :search_results, :fetch_results, :connection_error, :auth_error

    def initialize
      @disconnected = false
      @authenticated = false
      @examined_folder = nil
      @search_results = {}
      @fetch_results = {}
      @connection_error = nil
      @auth_error = nil
    end

    # Configure mock behavior
    def configure_search_results(criteria_key, message_ids)
      @search_results[criteria_key] = message_ids
    end

    def configure_fetch_results(message_ids, email_data)
      Array(message_ids).each do |id|
        @fetch_results[id] = email_data[id] if email_data[id]
      end
    end

    def configure_connection_error(error)
      @connection_error = error
    end

    def configure_auth_error(error)
      @auth_error = error
    end

    # IMAP interface methods
    def examine(folder)
      raise @connection_error if @connection_error
      @examined_folder = folder
    end

    def login(email, password)
      raise @auth_error if @auth_error
      @authenticated = true
    end

    def authenticate(method, *args)
      raise @auth_error if @auth_error
      @authenticated = true
    end

    def search(criteria)
      # Convert criteria array to string for matching
      criteria_key = criteria.is_a?(Array) ? criteria.join("_") : criteria.to_s
      @search_results[criteria_key] || []
    end

    def fetch(message_ids, attrs)
      Array(message_ids).map do |id|
        MockFetchData.new(id, @fetch_results[id] || {})
      end
    end

    def disconnect
      @disconnected = true
    end

    def disconnected?
      @disconnected
    end
  end

  # Mock fetch data structure
  class MockFetchData
    def initialize(uid, email_data)
      @uid = uid
      @email_data = email_data
    end

    def attr
      {
        "UID" => @uid,
        "FLAGS" => [ :Seen ],
        "RFC822" => @email_data[:raw_content] || generate_mock_email_content
      }
    end

    private

    def generate_mock_email_content
      "From: test@example.com\r\nSubject: Test\r\nDate: #{Time.current.rfc2822}\r\n\r\nTest email body"
    end
  end

  # Email Fixture Library
  module EmailFixtures
    # Costa Rican bank email samples
    def self.bac_transaction_email
      @bac_transaction_email ||= {
        from: "notificacion@notificacionesbaccr.com",
        subject: "Compra aprobada - BAC Credomatic",
        date: 1.day.ago,
        body: <<~EMAIL.strip,
          Estimado cliente,

          Su transacción ha sido aprobada:

          Tarjeta: ****1234
          Comercio: SUPERMERCADO MAS X MENOS
          Monto: ₡25,500.00
          Fecha: 15/08/2025 14:30:00
          Autorización: 123456

          Gracias por usar BAC Credomatic.
        EMAIL
        raw_content: nil
      }.tap { |email| email[:raw_content] = generate_raw_content(email) }
    end

    def self.bcr_transaction_email
      @bcr_transaction_email ||= {
        from: "alertas@bncr.fi.cr",
        subject: "Alerta BCR - Compra con tarjeta",
        date: 2.days.ago,
        body: <<~EMAIL.strip,
          Hola,

          Se realizó una compra con su tarjeta BCR:

          Tarjeta terminada en: 5678
          Establecimiento: AUTO MERCADO ESCAZU
          Importe: $45.20
          Fecha y hora: 14/08/2025 16:45

          Si no reconoce esta transacción, contacte al BCR.
        EMAIL
        raw_content: nil
      }.tap { |email| email[:raw_content] = generate_raw_content(email) }
    end

    def self.scotiabank_transaction_email
      @scotiabank_transaction_email ||= {
        from: "notificaciones@scotiabank.com",
        subject: "Scotiabank Alert - Purchase Notification",
        date: 3.days.ago,
        body: <<~EMAIL.strip,
          Dear Customer,

          A purchase was made with your Scotiabank card:

          Card ending in: 9012
          Merchant: WALMART SUPERCENTER
          Amount: $89.75
          Date: Aug 13, 2025, 19:22
          Reference: TXN789012

          Thank you for banking with Scotiabank.
        EMAIL
        raw_content: nil
      }.tap { |email| email[:raw_content] = generate_raw_content(email) }
    end

    def self.promotional_email
      @promotional_email ||= {
        from: "promociones@scotiabankca.net",
        subject: "¡Nuevas ofertas especiales para usted!",
        date: 1.day.ago,
        body: <<~EMAIL.strip,
          ¡Aprovecha nuestras ofertas especiales!

          - 50% descuento en seguros
          - Préstamos con tasa preferencial
          - Nuevas tarjetas de crédito

          ¡No te pierdas estas oportunidades!
        EMAIL
        raw_content: nil
      }.tap { |email| email[:raw_content] = generate_raw_content(email) }
    end

    def self.non_transaction_email
      @non_transaction_email ||= {
        from: "info@example.com",
        subject: "Newsletter - Financial Tips",
        date: 1.day.ago,
        body: <<~EMAIL.strip,
          Welcome to our financial newsletter!

          This week's tips:
          1. Save 10% of your income
          2. Review your budget monthly
          3. Consider investment options

          Happy saving!
        EMAIL
        raw_content: nil
      }.tap { |email| email[:raw_content] = generate_raw_content(email) }
    end

    # Generate raw email content for fixtures
    def self.generate_raw_content(email_data)
      headers = [
        "From: #{email_data[:from]}",
        "Subject: #{email_data[:subject]}",
        "Date: #{email_data[:date].rfc2822}",
        "Message-ID: <#{SecureRandom.uuid}@example.com>",
        "Content-Type: text/plain; charset=UTF-8",
        ""
      ].join("\r\n")

      headers + email_data[:body]
    end
  end

  # Test utilities
  def create_mock_imap
    MockIMAP.new
  end

  def setup_imap_mock_with_emails(mock_imap, email_fixtures)
    # Configure search results - use various search criteria patterns
    message_ids = (1..email_fixtures.length).to_a

    # The real service builds criteria as arrays, so we need to match this format
    # Set a default response for any search criteria to return our message IDs
    allow(mock_imap).to receive(:search).and_return(message_ids)

    # Configure fetch results
    fetch_data = {}
    email_fixtures.each_with_index do |fixture, index|
      fetch_data[index + 1] = fixture
    end
    mock_imap.configure_fetch_results(message_ids, fetch_data)
  end

  def stub_imap_connection(mock_imap)
    allow(Net::IMAP).to receive(:new).and_return(mock_imap)
  end

  def stub_processing_dependencies
    # Stub MonitoringService
    allow(Infrastructure::MonitoringService::ErrorTracker).to receive(:report)

    # Stub categorization engine
    mock_engine = double("categorization_engine")
    allow(Categorization::Engine).to receive(:create).and_return(mock_engine)
    allow(mock_engine).to receive(:categorize).and_return(
      double(successful?: true, confidence: 0.8, method: "pattern", category: nil)
    )

    mock_engine
  end

  def create_processed_email(email_account, message_id)
    FactoryBot.create(:processed_email,
      email_account: email_account,
      message_id: message_id,
      processed_at: 1.hour.ago
    )
  end

  # Create isolated email account for test
  def create_isolated_email_account(traits = [], **attributes)
    # Ensure unique email to prevent conflicts
    unique_email = "test_#{SecureRandom.hex(8)}@#{SecureRandom.hex(4)}.com"

    # Set minimal default attributes - let traits handle the rest
    default_attributes = {
      email: unique_email
    }

    # Only add defaults if not overridden by traits or explicit attributes
    default_attributes[:provider] = "gmail" unless attributes.key?(:provider)
    default_attributes[:bank_name] = "BAC" unless attributes.key?(:bank_name)

    # Only set active: true if :inactive trait is NOT present and active is not explicitly set
    if !traits.include?(:inactive) && !attributes.key?(:active)
      default_attributes[:active] = true
    end

    # Create with attributes that won't override trait behavior
    final_attributes = attributes.merge(default_attributes.except(*attributes.keys))
    FactoryBot.create(:email_account, *traits, **final_attributes)
  end

  # Create isolated parsing rule with unique bank name if needed
  def create_isolated_parsing_rule(bank_name, **attributes)
    # Clean existing rules for this bank to prevent conflicts
    ParsingRule.where(bank_name: bank_name).delete_all

    FactoryBot.create(:parsing_rule, bank_name: bank_name, **attributes)
  end

  # Custom matchers
  RSpec::Matchers.define :be_valid_processing_response do
    match do |response|
      response.is_a?(Hash) &&
        response.key?(:success) &&
        response.key?(:metrics) &&
        (response[:success] ? response.key?(:details) : response.key?(:error))
    end

    failure_message do |response|
      "expected #{response} to be a valid processing response with :success, :metrics, and either :details or :error keys"
    end
  end

  RSpec::Matchers.define :have_metrics_structure do
    match do |metrics|
      metrics.is_a?(Hash) &&
        metrics.key?(:emails_found) &&
        metrics.key?(:emails_processed) &&
        metrics.key?(:expenses_created) &&
        metrics.key?(:processing_time) &&
        metrics.values.all? { |v| v.is_a?(Numeric) }
    end

    failure_message do |metrics|
      "expected #{metrics} to have proper metrics structure with numeric values"
    end
  end
end

RSpec.configure do |config|
  config.include EmailProcessingTestHelper, type: :service
end

# Include EmailServiceIsolation for email service tests
RSpec.configure do |config|
  config.include EmailServiceIsolation, type: :service, integration: true
  config.include BankSpecificIsolation, type: :service, unit: true
end
