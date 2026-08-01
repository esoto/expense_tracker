require 'rails_helper'

# Security fix (2026-08 audit): QueuedEmailPayload exists so ProcessEmailJob
# never receives the raw bank-email body as a plain job argument — Active Job
# would otherwise serialize it into solid_queue_jobs.arguments (and
# ready/failed_executions) as plaintext, readable by anyone with DB access on
# the shared personal-blog-db host.
RSpec.describe QueuedEmailPayload, type: :model, unit: true do
  describe 'associations' do
    it { is_expected.to belong_to(:email_account) }
    it { is_expected.to belong_to(:sync_session).optional }
  end

  describe 'factory' do
    it 'creates a valid record' do
      payload = build(:queued_email_payload)
      expect(payload).to be_valid
    end
  end

  describe 'dependent destroy from email_account' do
    it 'is destroyed when email_account is destroyed' do
      payload = create(:queued_email_payload)
      email_account = payload.email_account

      expect { email_account.destroy }.to change(described_class, :count).by(-1)
    end
  end

  describe 'dependent nullify from sync_session' do
    it 'nullifies sync_session_id when sync_session is destroyed' do
      sync_session = create(:sync_session)
      payload = create(:queued_email_payload, sync_session: sync_session)

      sync_session.destroy

      expect(payload.reload.sync_session_id).to be_nil
    end
  end

  # THE core encryption guarantee: the encrypted column must never hold
  # readable plaintext, and it must round-trip transparently for the
  # application.
  describe 'encryption' do
    it 'encrypts encrypted_payload at rest' do
      expect(described_class.type_for_attribute(:encrypted_payload).class).to be(
        ActiveRecord::Encryption::EncryptedAttributeType
      )
    end

    it 'stores ciphertext in the underlying column (not plaintext)' do
      plaintext_marker = "BANK PII #{SecureRandom.hex(8)}"
      create(:queued_email_payload, payload_data: { email_data: { body: plaintext_marker } })

      raw_row = ActiveRecord::Base.connection.execute(
        "SELECT encrypted_payload FROM queued_email_payloads ORDER BY id DESC LIMIT 1"
      ).first
      expect(raw_row["encrypted_payload"]).not_to include(plaintext_marker)
    end

    it 'round-trips a hash with symbol keys, a Time value, and nested pre_parsed data' do
      now = Time.zone.parse("2026-08-01 12:00:00")
      data = {
        email_data: { body: "some bank text", subject: "Alert", date: now },
        pre_parsed: { amount: "123.45", merchant_name: "Store ABC" }
      }
      payload = create(:queued_email_payload, payload_data: data)
      payload.reload

      restored = payload.payload_data
      expect(restored[:email_data][:body]).to eq("some bank text")
      expect(restored[:email_data][:subject]).to eq("Alert")
      expect(restored[:email_data][:date]).to eq(now)
      expect(restored[:pre_parsed][:amount]).to eq("123.45")
      expect(restored[:pre_parsed][:merchant_name]).to eq("Store ABC")
    end

    it 'returns nil payload_data when encrypted_payload is blank' do
      payload = build(:queued_email_payload)
      payload.encrypted_payload = nil
      expect(payload.payload_data).to be_nil
    end
  end

  describe 'scopes' do
    let!(:processed_recent) { create(:queued_email_payload, :processed) }
    let!(:unprocessed_recent) { create(:queued_email_payload) }

    let!(:processed_expired) do
      create(:queued_email_payload, :processed).tap do |p|
        p.update_columns(processed_at: (QueuedEmailPayload::PROCESSED_RETENTION + 1.day).ago)
      end
    end

    let!(:unprocessed_expired) do
      create(:queued_email_payload).tap do |p|
        p.update_columns(created_at: (QueuedEmailPayload::UNPROCESSED_RETENTION + 1.day).ago)
      end
    end

    describe '.processed' do
      it 'returns only rows with a processed_at' do
        expect(described_class.processed).to contain_exactly(processed_recent, processed_expired)
      end
    end

    describe '.unprocessed' do
      it 'returns only rows without a processed_at' do
        expect(described_class.unprocessed).to contain_exactly(unprocessed_recent, unprocessed_expired)
      end
    end

    describe '.expired_processed' do
      it 'returns only processed rows past PROCESSED_RETENTION' do
        expect(described_class.expired_processed).to contain_exactly(processed_expired)
      end
    end

    describe '.expired_unprocessed' do
      it 'returns only unprocessed rows past UNPROCESSED_RETENTION' do
        expect(described_class.expired_unprocessed).to contain_exactly(unprocessed_expired)
      end
    end
  end

  describe '#mark_processed!' do
    it 'sets processed_at' do
      payload = create(:queued_email_payload)
      expect { payload.mark_processed! }.to change { payload.reload.processed_at }.from(nil)
    end
  end
end
