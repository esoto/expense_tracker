require 'rails_helper'

RSpec.describe EmailAccount, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      email_account = build(:email_account)
      expect(email_account).to be_valid
    end

    it 'requires email' do
      email_account = build(:email_account, email: nil)
      expect(email_account).not_to be_valid
      expect(email_account.errors[:email]).to include("can't be blank")
    end

    it 'validates email format' do
      email_account = build(:email_account, email: 'invalid-email')
      expect(email_account).not_to be_valid
      expect(email_account.errors[:email]).to include('is invalid')
    end

    it 'requires unique email' do
      create(:email_account, email: 'test@example.com')
      duplicate = build(:email_account, email: 'test@example.com')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end

    it 'requires provider' do
      email_account = build(:email_account, provider: nil)
      expect(email_account).not_to be_valid
      expect(email_account.errors[:provider]).to include("can't be blank")
    end

    it 'validates provider inclusion' do
      valid_providers = ['gmail', 'outlook', 'yahoo', 'custom', 'manual']
      valid_providers.each do |provider|
        email_account = build(:email_account, provider: provider)
        expect(email_account).to be_valid, "#{provider} should be valid"
      end

      invalid_email_account = build(:email_account, provider: 'invalid')
      expect(invalid_email_account).not_to be_valid
      expect(invalid_email_account.errors[:provider]).to include('is not included in the list')
    end

    it 'requires bank_name' do
      email_account = build(:email_account, bank_name: nil)
      expect(email_account).not_to be_valid
      expect(email_account.errors[:bank_name]).to include("can't be blank")
    end

    it 'validates Costa Rican bank names' do
      costa_rican_banks = ['BCR', 'BAC', 'Scotiabank', 'Banco Nacional']
      costa_rican_banks.each do |bank|
        email_account = build(:email_account, bank_name: bank)
        expect(email_account).to be_valid, "#{bank} should be valid"
      end
    end

    it 'allows blank encrypted_password since no validation exists' do
      email_account = build(:email_account, encrypted_password: '')
      expect(email_account).to be_valid
    end
  end

  describe 'associations' do
    let(:email_account) { create(:email_account) }

    it 'has many expenses' do
      expect(email_account).to respond_to(:expenses)
    end

    it 'belongs to parsing rule through bank name' do
      parsing_rule = create(:parsing_rule, bank_name: email_account.bank_name)
      expect(email_account.parsing_rules).to include(parsing_rule)
    end
  end

  describe 'scopes' do
    let!(:active_account) { create(:email_account, :gmail, active: true) }
    let!(:inactive_account) { create(:email_account, :inactive) }

    it 'returns active accounts' do
      expect(EmailAccount.active).to include(active_account)
      expect(EmailAccount.active).not_to include(inactive_account)
    end

    it 'returns accounts for specific bank' do
      bac_account = create(:email_account, :bac)
      bcr_account = create(:email_account, :bcr)
      
      expect(EmailAccount.for_bank('BAC')).to include(bac_account)
      expect(EmailAccount.for_bank('BAC')).not_to include(bcr_account)
    end
  end

  describe 'instance methods' do
    let(:gmail_account) { build(:email_account, :gmail) }
    let(:custom_account) { build(:email_account, :custom) }

    describe '#imap_settings' do
      it 'returns Gmail IMAP settings for Gmail provider' do
        settings = gmail_account.imap_settings
        expect(settings[:address]).to eq('imap.gmail.com')
        expect(settings[:port]).to eq(993)
        expect(settings[:enable_ssl]).to be true
        expect(settings[:user_name]).to eq('test@gmail.com')
      end

      it 'returns custom settings for custom provider' do
        custom_account = create(:email_account, :custom)
        settings = custom_account.imap_settings
        expect(settings[:address]).to eq('custom.imap.com')
        expect(settings[:port]).to eq(993)
      end
    end

    describe '#active?' do
      it 'returns true for active account' do
        gmail_account.active = true
        expect(gmail_account).to be_active
      end

      it 'returns false for inactive account' do
        gmail_account.active = false
        expect(gmail_account).not_to be_active
      end
    end

    describe '#display_name' do
      it 'returns email and bank name' do
        expect(gmail_account.display_name).to eq('test@gmail.com (BAC)')
      end
    end
  end

  describe 'encryption' do
    let(:email_account) { create(:email_account, encrypted_password: 'secret_password') }

    it 'encrypts password' do
      # Password should be encrypted in database
      expect(email_account.read_attribute_before_type_cast(:encrypted_password)).not_to eq('secret_password')
    end

    it 'decrypts password when accessed' do
      # Password should be decrypted when accessed through the model
      expect(email_account.encrypted_password).to eq('secret_password')
    end
  end

  describe 'settings management' do
    let(:email_account) { create(:email_account, :custom) }

    it 'stores and retrieves settings as JSON' do
      settings_hash = { 'imap' => { 'server' => 'custom.imap.com', 'port' => 993 } }
      email_account.settings = settings_hash
      email_account.save!
      email_account.reload
      expect(email_account.settings).to eq(settings_hash)
    end

    it 'returns empty hash for blank settings' do
      email_account.encrypted_settings = nil
      expect(email_account.settings).to eq({})
    end

    it 'returns empty hash for invalid JSON in settings' do
      email_account.encrypted_settings = 'invalid json'
      expect(email_account.settings).to eq({})
    end
  end

  describe 'IMAP provider settings' do
    it 'returns outlook IMAP settings' do
      outlook_account = create(:email_account, provider: 'outlook', email: 'test@outlook.com')
      settings = outlook_account.imap_settings
      expect(settings[:address]).to eq('outlook.office365.com')
      expect(settings[:port]).to eq(993)
      expect(settings[:user_name]).to eq('test@outlook.com')
    end

    it 'returns yahoo IMAP settings' do
      yahoo_account = create(:email_account, provider: 'yahoo', email: 'test@yahoo.com')
      settings = yahoo_account.imap_settings
      expect(settings[:address]).to eq('imap.mail.yahoo.com')
      expect(settings[:port]).to eq(993)
      expect(settings[:user_name]).to eq('test@yahoo.com')
    end

    it 'returns manual provider settings with localhost defaults' do
      manual_account = create(:email_account, provider: 'manual', email: 'test@manual.com')
      settings = manual_account.imap_settings
      expect(settings[:address]).to eq('localhost')
      expect(settings[:port]).to eq(993)
    end

    it 'merges custom settings with provider defaults' do
      custom_account = create(:email_account, :custom)
      custom_settings = { 'imap' => { 'timeout' => 30, 'ssl_verify_mode' => 'none' } }
      custom_account.settings = custom_settings
      custom_account.save!
      settings = custom_account.imap_settings
      expect(settings['timeout']).to eq(30)
      expect(settings['ssl_verify_mode']).to eq('none')
    end
  end

  describe 'constants' do
    it 'defines Costa Rican banks' do
      expect(EmailAccount::COSTA_RICAN_BANKS).to include('BCR', 'BAC', 'Scotiabank', 'Banco Nacional')
      expect(EmailAccount::COSTA_RICAN_BANKS).to be_frozen
    end
  end
end
