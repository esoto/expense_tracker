# frozen_string_literal: true

# Test helper specifically for EmailProcessing::Processor testing
module EmailProcessingProcessorTestHelper
  # Mock IMAP service that simulates ImapConnectionService
  class MockImapService
    attr_reader :errors

    def initialize
      @errors = []
      @envelopes = {}
      @body_structures = {}
      @body_parts = {}
      @text_bodies = {}
    end

    def configure_envelope(message_id, envelope)
      @envelopes[message_id] = envelope
    end

    def configure_body_structure(message_id, structure)
      @body_structures[message_id] = structure
    end

    def configure_body_part(message_id, part, content)
      @body_parts[[ message_id, part ]] = content
    end

    def configure_text_body(message_id, content)
      @text_bodies[message_id] = content
    end

    def fetch_envelope(message_id)
      @envelopes[message_id]
    end

    def fetch_body_structure(message_id)
      @body_structures[message_id]
    end

    def fetch_body_part(message_id, part)
      @body_parts[[ message_id, part ]]
    end

    def fetch_text_body(message_id)
      @text_bodies[message_id]
    end

    def add_error(message)
      @errors << message
    end
  end

  # Mock envelope structure
  class MockEnvelope
    attr_accessor :subject, :date, :from

    def initialize(subject:, date: Time.current, from: nil)
      @subject = subject
      @date = date
      @from = from || [ MockAddress.new("test", "example.com") ]
    end
  end

  # Mock email address
  class MockAddress
    attr_reader :mailbox, :host

    def initialize(mailbox, host)
      @mailbox = mailbox
      @host = host
    end
  end

  # Mock body structure for multipart emails
  class MockBodyStructure
    attr_reader :media_type, :subtype, :parts

    def initialize(media_type: "TEXT", subtype: "PLAIN", multipart: false, parts: [])
      @media_type = media_type
      @subtype = subtype
      @multipart = multipart
      @parts = parts
    end

    def multipart?
      @multipart
    end
  end

  # Helper methods
  def create_mock_imap_service
    MockImapService.new
  end

  # Create properly structured IMAP errors
  def create_imap_error(error_class, message)
    require 'ostruct'
    response = OpenStruct.new(data: OpenStruct.new(text: message))
    error_class.new(response)
  end

  def create_imap_no_response_error(message = 'No response')
    create_imap_error(Net::IMAP::NoResponseError, message)
  end

  def create_imap_bad_response_error(message = 'Bad response')
    create_imap_error(Net::IMAP::BadResponseError, message)
  end

  def create_imap_bye_response_error(message = 'Bye response')
    create_imap_error(Net::IMAP::ByeResponseError, message)
  end

  def create_transaction_envelope(subject = "Notificación de transacción")
    MockEnvelope.new(
      subject: subject,
      date: 1.day.ago,
      from: [ MockAddress.new("notificacion", "bank.com") ]
    )
  end

  # Alias for consistency with test code
  def create_envelope(subject = "Notificación de transacción")
    create_transaction_envelope(subject)
  end

  def create_non_transaction_envelope
    MockEnvelope.new(
      subject: "Newsletter",
      date: 1.day.ago,
      from: [ MockAddress.new("news", "example.com") ]
    )
  end

  def create_multipart_body_structure
    MockBodyStructure.new(
      media_type: "MULTIPART",
      subtype: "ALTERNATIVE",
      multipart: true,
      parts: [
        MockBodyStructure.new(media_type: "TEXT", subtype: "PLAIN"),
        MockBodyStructure.new(media_type: "TEXT", subtype: "HTML")
      ]
    )
  end

  def create_html_only_body_structure
    MockBodyStructure.new(media_type: "TEXT", subtype: "HTML")
  end

  def create_plain_text_body_structure
    MockBodyStructure.new(media_type: "TEXT", subtype: "PLAIN")
  end

  def mock_parser_for_testing
    parser = instance_double(EmailProcessing::Parser)
    allow(EmailProcessing::Parser).to receive(:new).and_return(parser)
    parser
  end

  def mock_conflict_detection_service
    service = instance_double(ConflictDetectionService)
    allow(ConflictDetectionService).to receive(:new).and_return(service)
    service
  end

  def mock_metrics_collector
    collector = instance_double(MetricsCollector)
    allow(collector).to receive(:track_operation).and_yield
    collector
  end
end

RSpec.configure do |config|
  config.include EmailProcessingProcessorTestHelper,
    file_path: %r{spec/services/email_processing/processor}
end
