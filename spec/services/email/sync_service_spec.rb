require 'rails_helper'
require_relative '../../../app/services/email/sync_service'

RSpec.describe Services::Email::SyncService, integration: true do
  include EmailServiceIsolation
  let(:service) { described_class.new }

  describe '#sync_emails', integration: true do
    context 'with specific email account' do
      let(:email_account) { create(:email_account, :bac, email: "test_bac_#{SecureRandom.hex(4)}@test.com") }

      it 'syncs specific active account successfully' do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id)

        result = service.sync_emails(email_account_id: email_account.id)

        expect(result[:success]).to be true
        expect(result[:message]).to include(email_account.email)
        expect(result[:email_account]).to eq(email_account)
      end

      it 'raises SyncError for non-existent account' do
        expect {
          service.sync_emails(email_account_id: 99999)
        }.to raise_error(Email::SyncService::SyncError, "Cuenta de correo no encontrada.")
      end

      it 'raises SyncError for inactive account' do
        inactive_account = create(:email_account, :inactive, email: "test_inactive_#{SecureRandom.hex(4)}@test.com")

        # Verify the account is actually inactive
        expect(inactive_account.active).to be false

        expect {
          service.sync_emails(email_account_id: inactive_account.id)
        }.to raise_error(Email::SyncService::SyncError, "La cuenta de correo está inactiva.")
      end
    end

    context 'without email account (sync all)' do
      around do |example|
        # Use a completely isolated database transaction for these tests
        EmailAccount.transaction do
          # Deactivate all existing accounts
          EmailAccount.update_all(active: false)
          example.run
          raise ActiveRecord::Rollback # rollback the transaction after the test
        end
      end

      it 'syncs all active accounts successfully' do
        create(:email_account, :bac, email: "test_bac_#{SecureRandom.hex(4)}@test.com")
        create(:email_account, :gmail, email: "test_gmail_#{SecureRandom.hex(4)}@test.com")

        expect(ProcessEmailsJob).to receive(:perform_later).with(no_args)

        result = service.sync_emails

        expect(result[:success]).to be true
        expect(result[:message]).to include("2 cuentas de correo")
        expect(result[:account_count]).to eq(2)
      end

      it 'handles plural correctly for single account' do
        create(:email_account, :bac, email: "test_bac_#{SecureRandom.hex(4)}@test.com")

        expect(ProcessEmailsJob).to receive(:perform_later).with(no_args)

        result = service.sync_emails

        expect(result[:message]).to include("1 cuenta de correo")
        expect(result[:message]).not_to include("cuentas")
      end

      it 'raises SyncError when no active accounts exist' do
        expect {
          service.sync_emails
        }.to raise_error(Email::SyncService::SyncError, "No hay cuentas de correo activas configuradas.")
      end
    end
  end

  describe 'private methods', integration: true do
    describe '#sync_specific_account', integration: true do
      let(:email_account) { create(:email_account, :bac, email: "test_bac_#{SecureRandom.hex(4)}@test.com") }

      around do |example|
        # Use a completely isolated database transaction for these tests
        EmailAccount.transaction do
          # Deactivate all existing accounts
          EmailAccount.update_all(active: false)
          example.run
          raise ActiveRecord::Rollback # rollback the transaction after the test
        end
      end

      it 'validates account existence' do
        expect {
          service.send(:sync_specific_account, 99999)
        }.to raise_error(Email::SyncService::SyncError, "Cuenta de correo no encontrada.")
      end

      it 'validates account is active' do
        inactive_account = create(:email_account, :inactive, email: "test_inactive_#{SecureRandom.hex(4)}@test.com")

        expect {
          service.send(:sync_specific_account, inactive_account.id)
        }.to raise_error(Email::SyncService::SyncError, "La cuenta de correo está inactiva.")
      end

      it 'enqueues job for valid active account' do
        expect(ProcessEmailsJob).to receive(:perform_later).with(email_account.id)

        result = service.send(:sync_specific_account, email_account.id)

        expect(result[:success]).to be true
        expect(result[:email_account]).to eq(email_account)
      end
    end

    describe '#sync_all_accounts', integration: true do
      around do |example|
        # Use a completely isolated database transaction for these tests
        EmailAccount.transaction do
          # Deactivate all existing accounts
          EmailAccount.update_all(active: false)
          example.run
          raise ActiveRecord::Rollback # rollback the transaction after the test
        end
      end

      it 'counts active accounts correctly' do
        create(:email_account, :bac, email: "test_bac_#{SecureRandom.hex(4)}@test.com")
        create(:email_account, :gmail, email: "test_gmail_#{SecureRandom.hex(4)}@test.com")
        create(:email_account, :inactive, email: "test_inactive_#{SecureRandom.hex(4)}@test.com")

        expect(ProcessEmailsJob).to receive(:perform_later).with(no_args)

        result = service.send(:sync_all_accounts)

        expect(result[:account_count]).to eq(2) # Only active accounts
      end

      it 'raises error when no active accounts' do
        expect {
          service.send(:sync_all_accounts)
        }.to raise_error(Email::SyncService::SyncError, "No hay cuentas de correo activas configuradas.")
      end

      context 'message pluralization' do
        it 'uses singular form for one account' do
          create(:email_account, email: "test_#{SecureRandom.hex(4)}@test.com")

          result = service.send(:sync_all_accounts)
          expect(result[:message]).to include("1 cuenta de correo")
          expect(result[:message]).not_to include("cuentas de correo")
        end

        it 'uses plural form for multiple accounts' do
          2.times { create(:email_account, email: "test_#{SecureRandom.hex(4)}@test.com") }

          result = service.send(:sync_all_accounts)
          expect(result[:message]).to include("2 cuentas de correo")
        end
      end
    end
  end

  describe 'SyncError', integration: true do
    it 'is a StandardError subclass' do
      expect(Email::SyncService::SyncError.new).to be_a(StandardError)
    end

    it 'accepts custom messages' do
      error = Email::SyncService::SyncError.new("Custom error message")
      expect(error.message).to eq("Custom error message")
    end
  end
end
