require 'rails_helper'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'Services::EmailProcessing::Processor - Idempotent Re-sync', type: :job, integration: true do
  include EmailProcessingProcessorTestHelper
  include ActiveJob::TestHelper

  let!(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:mock_imap_service) { create_mock_imap_service }
  let(:sequence_number) { 1 } # IMAP sequence number — unstable across sessions, fetch mechanics only
  let(:rfc_message_id) { '<stable-id-123@mail.bank.example>' }

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

  let(:different_bac_email) do
    <<~EMAIL
      Estimado cliente,

      Le informamos sobre una transacción realizada con su tarjeta de débito BAC:

      Comercio: OTRO COMERCIO XYZ
      Ciudad: HEREDIA
      Fecha: Ago 2, 2025, 09:30
      Monto: CRC 12,345.00
      Tipo de Transacción: COMPRA

      Si no reconoce esta transacción, contacte inmediatamente al centro de atención al cliente.
    EMAIL
  end

  def configure_message(seq, message_id:, body:)
    mock_imap_service.configure_envelope(seq, create_transaction_envelope('Notificación de transacción', message_id: message_id))
    mock_imap_service.configure_body_structure(seq, create_plain_text_body_structure)
    mock_imap_service.configure_text_body(seq, body)
  end

  def run_sync
    result = nil
    perform_enqueued_jobs do
      result = Services::EmailProcessing::Processor.new(email_account)
                                                   .process_emails([ sequence_number ], mock_imap_service)
    end
    result
  end

  # The fetcher has no cursor — it searches by SINCE-date only
  # (fetcher.rb build_search_criteria), so a re-sync hands the Processor the
  # same window of messages again. Idempotency must key on the RFC822
  # Message-ID header, never the IMAP sequence number.
  it 'processes a message with the same RFC822 Message-ID only once across two re-syncs' do
    configure_message(sequence_number, message_id: rfc_message_id, body: sample_bac_email)

    first_result = run_sync

    expect(Expense.count).to eq(1)
    expect(ProcessedEmail.count).to eq(1)
    expect(ProcessedEmail.last.message_id).to eq('stable-id-123@mail.bank.example')
    expect(first_result[:processed_count]).to eq(1)

    second_result = run_sync

    # No new Expense, no new ProcessedEmail — the skip gate short-circuited
    # before any parsing or conflict-detection work happened.
    expect(Expense.count).to eq(1)
    expect(ProcessedEmail.count).to eq(1)
    expect(second_result[:processed_count]).to eq(0)
    expect(second_result[:total_count]).to eq(1)
  end

  # REGRESSION (architect review): RFC 3501 sequence numbers shift when
  # messages are expunged (routine with Gmail archiving), so on a later sync
  # the SAME sequence position can carry a DIFFERENT email. That email must
  # be processed — skipping it would silently drop a real expense.
  it 'creates a new expense when the same sequence number carries a different Message-ID' do
    configure_message(sequence_number, message_id: rfc_message_id, body: sample_bac_email)
    run_sync
    expect(Expense.count).to eq(1)

    # Same sequence position, different email (expunge shifted the mailbox)
    configure_message(sequence_number,
                      message_id: '<completely-different-id@mail.bank.example>',
                      body: different_bac_email)
    result = run_sync

    expect(result[:processed_count]).to eq(1)
    expect(Expense.count).to eq(2)
    expect(ProcessedEmail.count).to eq(2)
    expect(Expense.order(:created_at).last.merchant_name).to include('OTRO COMERCIO')
  end

  it 'processes a message with a nil Message-ID header normally and records nothing' do
    configure_message(sequence_number, message_id: nil, body: sample_bac_email)

    result = nil
    expect { result = run_sync }.not_to raise_error

    expect(result[:processed_count]).to eq(1)
    expect(Expense.count).to eq(1)
    expect(ProcessedEmail.count).to eq(0)
  end
end
