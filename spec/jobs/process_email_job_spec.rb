require 'rails_helper'

RSpec.describe ProcessEmailJob, type: :job, integration: true do
  # Keep using create for tests that need real database records
  let!(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
  let(:email_data) do
    {
      body: sample_bac_email,
      subject: "Notificación de transacción PTA LEONA SOC 01-08-2025 - 14:16",
      from: "notificaciones@bac.net",
      date: Time.current
    }
  end

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
    # No need for mocking since we're using real records
  end

  describe '#perform', integration: true do
    context 'with valid email account and data' do
      it 'creates an expense successfully' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, email_data)
        }.to change(Expense, :count).by(1)
      end

      it 'logs successful expense creation' do
        allow(Rails.logger).to receive(:info)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        created_expense = Expense.last
        expect(Rails.logger).to have_received(:info).with(
          "Successfully created expense: #{created_expense.id} - #{created_expense.formatted_amount}"
        )
      end

      it 'logs processing start' do
        allow(Rails.logger).to receive(:info)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        expect(Rails.logger).to have_received(:info).with(
          "Processing individual email for: #{email_account.email}"
        )
      end

      it 'logs only non-sensitive email metadata in debug mode' do
        allow(Rails.logger).to receive(:debug)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        expect(Rails.logger).to have_received(:debug).with(
          "Email data: subject=#{email_data[:subject].inspect}, message_id=#{email_data[:message_id].inspect}"
        )
      end

      it 'never writes the email body (bank PII) to the debug log' do
        allow(Rails.logger).to receive(:debug)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        expect(Rails.logger).not_to have_received(:debug).with(/#{Regexp.escape(email_data[:body])}/)
      end

      it 'creates expense with correct attributes' do
        ProcessEmailJob.new.perform(email_account.id, email_data)

        expense = Expense.last
        expect(expense.email_account).to eq(email_account)
        expect(expense.amount).to eq(95000.0)
        expect(expense.currency).to eq('crc')
        expect(expense.status).to eq('processed')
      end
    end

    context 'with non-existent email account' do
      it 'does not create an expense' do
        expect {
          ProcessEmailJob.new.perform(99999, email_data)
        }.not_to change(Expense, :count)
      end

      it 'logs error for missing email account' do
        allow(Rails.logger).to receive(:error)

        ProcessEmailJob.new.perform(99999, email_data)

        expect(Rails.logger).to have_received(:error).with(
          "EmailAccount not found: 99999"
        )
      end

      it 'returns early without processing' do
        expect(Services::EmailProcessing::Parser).not_to receive(:new)

        ProcessEmailJob.new.perform(99999, email_data)
      end
    end

    context 'with invalid email data' do
      let(:invalid_email_data) do
        {
          body: "Invalid email content without required patterns",
          subject: "Random subject",
          from: "unknown@example.com"
        }
      end

      it 'does not create an expense and records parsing failure' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, invalid_email_data)
        }.to change(EmailParsingFailure, :count).by(1)

        # Verify no expense was created (only pre-existing ones)
        expect(Expense.where(status: 'failed')).to be_empty
      end

      it 'logs parsing failure' do
        allow(Rails.logger).to receive(:warn)

        ProcessEmailJob.new.perform(email_account.id, invalid_email_data)

        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/Failed to create expense from email/)
        )
      end

      it 'calls save_failed_parsing method' do
        job = ProcessEmailJob.new
        allow(job).to receive(:save_failed_parsing)

        job.perform(email_account.id, invalid_email_data)

        expect(job).to have_received(:save_failed_parsing).with(
          email_account,
          invalid_email_data,
          an_instance_of(Array)
        )
      end
    end

    context 'when Services::EmailProcessing::Parser raises an exception' do
      it 'handles parser exceptions gracefully' do
        allow(Services::EmailProcessing::Parser).to receive(:new).and_raise(StandardError.new("Parser error"))

        expect {
          ProcessEmailJob.new.perform(email_account.id, email_data)
        }.to raise_error(StandardError, "Parser error")
      end
    end
  end

  describe '#save_failed_parsing', integration: true do
    let(:job) { ProcessEmailJob.new }
    let(:errors) { [ "Amount not found", "Date format invalid" ] }
    let(:failed_email_data) do
      {
        body: "Failed email content",
        subject: "Failed subject"
      }
    end

    it 'creates an EmailParsingFailure record without creating an Expense' do
      expect {
        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      }.to change(EmailParsingFailure, :count).by(1)

      expect { job.send(:save_failed_parsing, email_account, failed_email_data, errors) }
        .not_to change(Expense, :count)
    end

    it 'sets correct attributes for parsing failure' do
      job.send(:save_failed_parsing, email_account, failed_email_data, errors)

      failure = EmailParsingFailure.last
      expect(failure.email_account).to eq(email_account)
      expect(failure.bank_name).to eq(email_account.bank_name)
      expect(failure.error_messages).to eq(errors)
      expect(failure.raw_email_content).to eq(failed_email_data[:body])
      expect(failure.original_email_size).to eq(failed_email_data[:body].bytesize)
      expect(failure.truncated).to eq(false)
    end

    context 'with large email body' do
      let(:large_body) { 'x' * 15_000 } # 15KB
      let(:large_email_data) { failed_email_data.merge(body: large_body) }

      it 'truncates large email bodies' do
        job.send(:save_failed_parsing, email_account, large_email_data, errors)

        failure = EmailParsingFailure.last
        expect(failure.raw_email_content.bytesize).to be <= 10_000 + 50 # 10KB + truncation message
        expect(failure.raw_email_content).to end_with('... [truncated]')
      end

      it 'marks as truncated' do
        job.send(:save_failed_parsing, email_account, large_email_data, errors)

        failure = EmailParsingFailure.last
        expect(failure.truncated).to eq(true)
        expect(failure.original_email_size).to eq(15_000)
      end
    end

    it 'handles save errors gracefully' do
      allow(EmailParsingFailure).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error)

      expect {
        job.send(:save_failed_parsing, email_account, failed_email_data, errors)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(
        a_string_matching(/Failed to save parsing failure record/)
      )
    end

    context 'when email_account is nil' do
      it 'handles nil email_account gracefully' do
        allow(Rails.logger).to receive(:error)

        expect {
          job.send(:save_failed_parsing, nil, failed_email_data, errors)
        }.not_to raise_error
      end
    end
  end

  describe 'job queue configuration', integration: true do
    it 'uses the email_processing queue' do
      expect(ProcessEmailJob.new.queue_name).to eq('email_processing')
    end
  end

  describe 'ActiveJob integration', integration: true do
    it 'can be enqueued with perform_later' do
      expect {
        ProcessEmailJob.perform_later(email_account.id, email_data)
      }.to have_enqueued_job(ProcessEmailJob).with(email_account.id, email_data)
    end

    it 'can be performed immediately' do
      expect {
        ProcessEmailJob.perform_now(email_account.id, email_data)
      }.to change(Expense, :count).by(1)
    end
  end

  describe 'sync session threading', integration: true do
    let(:small_email_data) { { subject: "Test", body: "Test body", date: Time.current } }

    it "works without sync_session_id for backwards compatibility" do
      expect { ProcessEmailJob.perform_now(email_account.id, small_email_data) }.not_to raise_error
    end

    it "uses explicit sync_session_id when provided" do
      sync_session = create(:sync_session, :running)
      # Should not call SyncSession.active.last
      expect(SyncSession).not_to receive(:active)
      ProcessEmailJob.perform_now(email_account.id, small_email_data, sync_session.id)
    end

    it "resolves nil when sync_session_id is nil" do
      expect(SyncSession).not_to receive(:active)
      ProcessEmailJob.perform_now(email_account.id, small_email_data, nil)
    end
  end

  describe 'edge cases', integration: true do
    context 'with empty email data' do
      let(:empty_email_data) { {} }

      it 'handles empty email data' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, empty_email_data)
        }.not_to raise_error
      end
    end

    context 'with nil email data' do
      it 'handles nil email data' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, nil)
        }.not_to raise_error
      end
    end

    context 'with string email account id' do
      it 'handles string id parameter' do
        expect {
          ProcessEmailJob.new.perform(email_account.id.to_s, email_data)
        }.to change(Expense, :count).by(1)
      end
    end
  end

  describe 'idempotent recording via ProcessedEmail', integration: true do
    # RFC822 Message-ID header as fetched from the ENVELOPE — the idempotency
    # key. Deliberately mixed-case and bracketed to exercise normalization.
    let(:rfc_message_id) { '<MSG-Abc-123@Mail.Gmail.Com>' }
    let(:email_data_with_rfc_id) { email_data.merge(message_id: 7, rfc_message_id: rfc_message_id) }

    it 'records a ProcessedEmail keyed on the normalized RFC822 Message-ID when the expense is created' do
      expect {
        ProcessEmailJob.new.perform(email_account.id, email_data_with_rfc_id)
      }.to change(ProcessedEmail, :count).by(1)

      recorded = ProcessedEmail.last
      expect(recorded.message_id).to eq('msg-abc-123@mail.gmail.com')
      expect(recorded.email_account).to eq(email_account)
      expect(recorded.user).to eq(email_account.user)
      expect(recorded.subject).to eq(email_data_with_rfc_id[:subject])
    end

    it 'never uses the IMAP sequence number as the recorded key' do
      ProcessEmailJob.new.perform(email_account.id, email_data_with_rfc_id)

      expect(ProcessedEmail.where(message_id: '7')).to be_empty
    end

    it 'records a ProcessedEmail for the duplicate email without corrupting the original expense status' do
      ProcessEmailJob.new.perform(email_account.id, email_data_with_rfc_id)

      expect {
        ProcessEmailJob.new.perform(email_account.id, email_data_with_rfc_id.merge(rfc_message_id: '<resent-copy@mail.gmail.com>'))
      }.to change(Expense, :count).by(0).and change(ProcessedEmail, :count).by(1)

      # The original expense is the survivor, not the duplicate — its status
      # must stay `processed`. See fix(parser): stop flagging the existing
      # expense as duplicate when a duplicate email arrives.
      expect(Expense.last.status).to eq('processed')
    end

    it 'does not record a ProcessedEmail when parsing fails (non-terminal outcome)' do
      invalid_email_data = { body: "Invalid email content", subject: "Random subject", rfc_message_id: rfc_message_id }

      expect {
        ProcessEmailJob.new.perform(email_account.id, invalid_email_data)
      }.not_to change(ProcessedEmail, :count)
    end

    it 'does not record and does not raise when the RFC822 Message-ID header is missing' do
      expect {
        ProcessEmailJob.new.perform(email_account.id, email_data.merge(rfc_message_id: nil))
      }.not_to change(ProcessedEmail, :count)
    end

    it 'does not record when the header is bracket-only garbage' do
      expect {
        ProcessEmailJob.new.perform(email_account.id, email_data.merge(rfc_message_id: '<>'))
      }.not_to change(ProcessedEmail, :count)
    end

    it 'does not raise when recording fails' do
      allow(ProcessedEmail).to receive(:find_or_create_by!).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)

      expect {
        ProcessEmailJob.new.perform(email_account.id, email_data_with_rfc_id)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(
        a_string_matching(/Failed to record processed email/)
      )
    end
  end

  # Security fix (2026-08 audit): ProcessEmailJob's second argument used to
  # always be the raw email_data Hash (plaintext bank PII, serialized into
  # solid_queue_jobs.arguments). It is now a QueuedEmailPayload id, with a
  # Hash still accepted for deploy-window compatibility (in-flight jobs
  # enqueued before this fix shipped).
  describe 'QueuedEmailPayload argument handling (2026-08 security fix)', integration: true do
    context 'with a QueuedEmailPayload id (current path)' do
      let!(:payload) do
        QueuedEmailPayload.create!(
          email_account: email_account,
          payload_data: { email_data: email_data, pre_parsed: nil }
        )
      end

      it 'creates an expense from the payload record data' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, payload.id)
        }.to change(Expense, :count).by(1)
      end

      it 'marks the payload record as processed' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, payload.id)
        }.to change { payload.reload.processed_at }.from(nil)
      end

      it 'passes the sync_session id through unchanged' do
        sync_session = create(:sync_session, user: email_account.user)
        payload_with_session = QueuedEmailPayload.create!(
          email_account: email_account,
          sync_session: sync_session,
          payload_data: { email_data: email_data, pre_parsed: nil }
        )

        expect(Services::SyncMetricsCollector).to receive(:new).with(sync_session).and_call_original

        ProcessEmailJob.new.perform(email_account.id, payload_with_session.id, sync_session.id)
      end

      it 'restores pre_parsed data (e.g. String amount) from the payload record' do
        pre_parsed = {
          amount: "95000.50",
          transaction_date: Date.current.to_s,
          merchant_name: "PTA LEONA SOC",
          description: "Purchase",
          email_account_id: email_account.id,
          raw_email_content: sample_bac_email
        }
        payload_with_pre_parsed = QueuedEmailPayload.create!(
          email_account: email_account,
          payload_data: { email_data: email_data, pre_parsed: pre_parsed }
        )

        ProcessEmailJob.new.perform(email_account.id, payload_with_pre_parsed.id)

        expect(Expense.last.amount).to eq(95000.50)
      end
    end

    context 'with a legacy plaintext Hash (deploy-window compatibility)' do
      it 'still creates an expense (in-flight pre-deploy jobs must keep working)' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, email_data)
        }.to change(Expense, :count).by(1)
      end

      it 'logs a deprecation warning' do
        allow(Rails.logger).to receive(:warn)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/Deprecated.*legacy plaintext email_data Hash/))
      end

      it 'does not touch QueuedEmailPayload at all' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, email_data)
        }.not_to change(QueuedEmailPayload, :count)
      end
    end

    context 'with a missing/deleted payload record' do
      it 'does not raise and does not create an expense' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, 999_999_999)
        }.not_to change(Expense, :count)
      end

      it 'logs an error identifying the missing payload id' do
        allow(Rails.logger).to receive(:error)

        ProcessEmailJob.new.perform(email_account.id, 999_999_999)

        expect(Rails.logger).to have_received(:error).with(a_string_matching(/QueuedEmailPayload 999999999 not found/))
      end

      it 'does not call the parser at all' do
        expect(Services::EmailProcessing::Parser).not_to receive(:new)
        ProcessEmailJob.new.perform(email_account.id, 999_999_999)
      end
    end

    context 'with an unrecognized argument type' do
      it 'logs an error and does not raise' do
        allow(Rails.logger).to receive(:error)

        expect {
          ProcessEmailJob.new.perform(email_account.id, 3.14)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(a_string_matching(/Unrecognized argument type/))
      end
    end
  end

  # Review findings (2026-08 audit follow-up): a failure in mark_processed!
  # used to propagate all the way up through perform, which would re-trigger
  # this job's own retry_on and re-parse an already-persisted expense —
  # flipping it to status: :duplicate via Parser's duplicate branch. See the
  # rescue around mark_processed! and the processed_at early exit in
  # #resolve_email_payload.
  describe 'retry-corruption hardening (review findings)', integration: true do
    let!(:payload) do
      QueuedEmailPayload.create!(
        email_account: email_account,
        payload_data: { email_data: email_data, pre_parsed: nil }
      )
    end

    context 'when mark_processed! raises' do
      it 'does not raise, leaves the expense processed, and logs the error' do
        allow_any_instance_of(QueuedEmailPayload).to receive(:update!).and_raise(ActiveRecord::Deadlocked)
        allow(Rails.logger).to receive(:error)

        expense = nil
        expect {
          expense = ProcessEmailJob.new.perform(email_account.id, payload.id)
        }.not_to raise_error

        expect(expense.status).to eq('processed')
        expect(Rails.logger).to have_received(:error).with(
          a_string_matching(/Failed to mark QueuedEmailPayload #{payload.id} as processed.*ActiveRecord::Deadlocked/)
        )
      end
    end

    context 'when the same payload id is replayed after it was already processed' do
      it 'does not invoke the parser again and leaves the expense unchanged' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, payload.id)
        }.to change(Expense, :count).by(1)

        expense = Expense.last
        expect(payload.reload.processed_at).to be_present

        expect(Services::EmailProcessing::Parser).not_to receive(:new)

        expect {
          ProcessEmailJob.new.perform(email_account.id, payload.id)
        }.not_to change(Expense, :count)

        expect(expense.reload.status).to eq('processed')
      end

      it 'logs that the replayed enqueue was skipped' do
        ProcessEmailJob.new.perform(email_account.id, payload.id)

        allow(Rails.logger).to receive(:warn)
        ProcessEmailJob.new.perform(email_account.id, payload.id)

        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/QueuedEmailPayload #{payload.id} already processed at.*skipping re-parse/)
        )
      end
    end

    context 'when the stored payload is corrupted' do
      let!(:corrupted_payload) do
        QueuedEmailPayload.create!(email_account: email_account, payload_data: { email_data: email_data, pre_parsed: nil })
      end

      before { corrupted_payload.update_column(:encrypted_payload, "not valid json or ciphertext") }

      it 'does not crash and logs a distinct corruption error' do
        allow(Rails.logger).to receive(:error)

        expect {
          ProcessEmailJob.new.perform(email_account.id, corrupted_payload.id)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(
          a_string_matching(/QueuedEmailPayload #{corrupted_payload.id} found but payload_data is blank \(corrupted\/unreadable\)/)
        )
      end

      it 'does not create an expense' do
        expect {
          ProcessEmailJob.new.perform(email_account.id, corrupted_payload.id)
        }.not_to change(Expense, :count)
      end
    end
  end
end
