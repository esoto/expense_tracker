require 'rails_helper'
require 'support/email_processing_processor_test_helper'

# fix/silent-duplicate-skip: PR #548 made a re-sync of the IDENTICAL email
# (same RFC822 Message-ID) skip via ProcessedEmail before conflict detection
# is ever reached. This spec covers the case that still reaches
# ConflictDetectionService: the SAME transaction arriving under two
# DIFFERENT Message-IDs within the same sync window (e.g. the bank resends
# the notification, or two overlapping sync windows both pick it up).
#
# Exercises the real ConflictDetectionService (no mocks) end-to-end through
# Processor#process_emails, to prove the duplicate is discarded silently —
# no SyncConflict row — while still leaving an auditable soft-deleted
# Expense and a normal ProcessedEmail record.
RSpec.describe 'Services::EmailProcessing::Processor - Silent Duplicate Skip', type: :job, integration: true do
  include EmailProcessingProcessorTestHelper
  include ActiveJob::TestHelper

  let!(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:sync_session) { create(:sync_session, user: email_account.user) }
  let(:mock_imap_service) { create_mock_imap_service }

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

  def configure_message(seq, message_id:, body:)
    mock_imap_service.configure_envelope(seq, create_transaction_envelope('Notificación de transacción', message_id: message_id))
    mock_imap_service.configure_body_structure(seq, create_plain_text_body_structure)
    mock_imap_service.configure_text_body(seq, body)
  end

  def run_sync(sequence_number)
    result = nil
    perform_enqueued_jobs do
      result = Services::EmailProcessing::Processor.new(email_account, sync_session: sync_session)
                                                     .process_emails([ sequence_number ], mock_imap_service)
    end
    result
  end

  it 'silently skips a same-window duplicate (different Message-ID) without creating a SyncConflict' do
    configure_message(1, message_id: '<first-55@mail.bank.example>', body: sample_bac_email)
    configure_message(2, message_id: '<second-55@mail.bank.example>', body: sample_bac_email)

    first_result = run_sync(1)
    expect(first_result[:processed_count]).to eq(1)
    expect(first_result[:detected_expenses_count]).to eq(1)
    expect(Expense.count).to eq(1)

    second_result = run_sync(2)

    # Processed (terminal outcome reached) but no new expense was enqueued.
    expect(second_result[:processed_count]).to eq(1)
    expect(second_result[:detected_expenses_count]).to eq(0)

    # No real second expense — only the original, real one is visible...
    expect(Expense.count).to eq(1)
    # ...but the incoming duplicate WAS saved (soft-deleted) for audit/history.
    expect(Expense.unscoped.count).to eq(2)
    duplicate = Expense.unscoped.order(:created_at).last
    expect(duplicate.status).to eq('duplicate')
    expect(duplicate.deleted_at).to be_present

    # The whole point of this fix: no SyncConflict noise for exact/duplicate
    # re-detections — only genuinely ambiguous (70-89%) cases would create one.
    expect(SyncConflict.count).to eq(0)

    # Both emails reached a terminal outcome and are recorded so a future
    # re-sync of either Message-ID short-circuits before conflict detection.
    expect(ProcessedEmail.count).to eq(2)
  end
end
