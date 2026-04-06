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

      it 'logs email data in debug mode' do
        allow(Rails.logger).to receive(:debug)

        ProcessEmailJob.new.perform(email_account.id, email_data)

        expect(Rails.logger).to have_received(:debug).with(
          "Email data: #{email_data.inspect}"
        )
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
end
