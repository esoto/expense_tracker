require 'rails_helper'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'Services::EmailProcessing::Processor - Idempotent Re-sync', type: :job, integration: true do
  include EmailProcessingProcessorTestHelper
  include ActiveJob::TestHelper

  let!(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:mock_imap_service) { create_mock_imap_service }
  let(:message_id) { 1 }

  let(:sample_bac_email) do
    <<~EMAIL
      Estimado cliente,

      Le informamos sobre una transacción realizada con su tarjeta de débito BAC:

      Comercio: PTA LEONA SOC
      Ciudad: SAN JOSE
      Fecha: Ago 1, 2025, 14:16
      Monto: CRC 95,000.00
      Tipo de Transacción: COMPRA

      Si no reconoce esta transacción, contacte inmediatamente al centro de atención al cliente.
    EMAIL
  end

  before do
    mock_imap_service.configure_envelope(message_id, create_transaction_envelope)
    mock_imap_service.configure_body_structure(message_id, create_plain_text_body_structure)
    mock_imap_service.configure_text_body(message_id, sample_bac_email)
  end

  # Simulates re-syncing the exact same IMAP SINCE-date window twice — the
  # fetcher has no BEFORE/UID cursor (fetcher.rb:124-128), so the same
  # message_id is handed to the Processor on both syncs.
  it 'processes the same message only once across two re-syncs' do
    first_processor = Services::EmailProcessing::Processor.new(email_account)
    first_result = nil
    perform_enqueued_jobs do
      first_result = first_processor.process_emails([ message_id ], mock_imap_service)
    end

    expect(Expense.count).to eq(1)
    expect(ProcessedEmail.count).to eq(1)
    expect(first_result[:processed_count]).to eq(1)

    second_processor = Services::EmailProcessing::Processor.new(email_account)
    second_result = nil
    perform_enqueued_jobs do
      second_result = second_processor.process_emails([ message_id ], mock_imap_service)
    end

    # No new Expense, no new ProcessedEmail — the skip gate short-circuited
    # before any parsing or conflict-detection work happened.
    expect(Expense.count).to eq(1)
    expect(ProcessedEmail.count).to eq(1)
    expect(second_result[:processed_count]).to eq(0)
    expect(second_result[:total_count]).to eq(1)
  end
end
