require 'rails_helper'

RSpec.describe EmailAccount, type: :model, unit: true do
  # Use build for shoulda-matchers that need valid models
  subject(:email_account) { build(:email_account) }

  describe 'associations' do
    it { should have_many(:expenses).dependent(:destroy) }
    it { should have_many(:budgets).dependent(:destroy) }
    it { should have_many(:parsing_rules).with_foreign_key(:bank_name) }
    it { should have_many(:sync_session_accounts).dependent(:destroy) }
    it { should have_many(:user_category_preferences).dependent(:destroy) }
    it { should have_many(:sync_metrics).dependent(:destroy) }
    it { should have_many(:categories).through(:expenses) }
  end

  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email) }
    it { should allow_value("unique_#{SecureRandom.hex(4)}@example.com").for(:email) }
    it { should_not allow_value('invalid-email').for(:email) }
    it { should validate_presence_of(:provider) }
    it { should validate_inclusion_of(:provider).in_array([ "gmail", "outlook", "yahoo", "custom", "manual" ]) }
    it { should validate_presence_of(:bank_name) }
  end

  describe 'constants' do
    it 'defines COSTA_RICAN_BANKS constant' do
      expect(EmailAccount::COSTA_RICAN_BANKS).to be_an(Array)
      expect(EmailAccount::COSTA_RICAN_BANKS).to include(
        'BCR', 'Banco de Costa Rica',
        'BAC', 'BAC San José',
        'Scotiabank',
        'Banco Nacional', 'BNCR',
        'Banco Popular',
        'Davivienda',
        'Coopeservidores',
        'Banco Cathay'
      )
    end

    it 'freezes COSTA_RICAN_BANKS to prevent modification' do
      expect(EmailAccount::COSTA_RICAN_BANKS).to be_frozen
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'filters by active status' do
        expect(EmailAccount.active.to_sql).to include('"email_accounts"."active" = ')
      end
    end

    describe '.for_bank' do
      it 'filters by bank_name' do
        sql = EmailAccount.for_bank('BAC').to_sql
        expect(sql).to include('bank_name')
        expect(sql).to include('BAC')
      end
    end
  end

  describe 'encryption' do
    it { should encrypt(:encrypted_password) }
    it { should encrypt(:encrypted_settings) }
  end

  describe 'instance methods' do
    describe '#display_name' do
      it 'returns email and bank name formatted' do
        email_account = build(:email_account, email: 'test@example.com', bank_name: 'BAC')
        expect(email_account.display_name).to eq('test@example.com (BAC)')
      end

      it 'handles special characters in bank name' do
        email_account = build(:email_account, email: 'test@example.com', bank_name: 'Bank & Trust')
        expect(email_account.display_name).to eq('test@example.com (Bank & Trust)')
      end
    end

    describe '#settings' do
      it 'returns empty hash when encrypted_settings is nil' do
        email_account = build(:email_account, encrypted_settings: nil)
        expect(email_account.settings).to eq({})
      end

      it 'returns empty hash when encrypted_settings is empty' do
        email_account = build(:email_account, encrypted_settings: '')
        expect(email_account.settings).to eq({})
      end

      it 'parses valid JSON from encrypted_settings' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"key":"value","nested":{"key2":"value2"}}'
        expect(email_account.settings).to eq({ 'key' => 'value', 'nested' => { 'key2' => 'value2' } })
      end

      it 'returns empty hash for invalid JSON' do
        email_account = build(:email_account)
        email_account.encrypted_settings = 'invalid json {'
        expect(email_account.settings).to eq({})
      end

      it 'handles JSON parse errors gracefully' do
        email_account = build(:email_account)
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError)
        expect(email_account.settings).to eq({})
      end
    end

    describe '#settings=' do
      it 'converts hash to JSON string' do
        email_account = build(:email_account)
        settings_hash = { 'key' => 'value', 'number' => 123 }
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end

      it 'handles nested hashes' do
        email_account = build(:email_account)
        settings_hash = { 'imap' => { 'server' => 'example.com', 'port' => 993 } }
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end

      it 'handles empty hash' do
        email_account = build(:email_account)
        email_account.settings = {}
        expect(email_account.encrypted_settings).to eq('{}')
      end

      it 'handles arrays in settings' do
        email_account = build(:email_account)
        settings_hash = { 'folders' => [ 'INBOX', 'Sent' ], 'flags' => [] }
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end
    end

    describe '#imap_settings' do
      it 'builds base settings with correct structure' do
        email_account = build(:email_account,
          email: 'test@example.com',
          encrypted_password: 'password123',
          provider: 'gmail'
        )

        settings = email_account.imap_settings

        expect(settings[:address]).to eq('imap.gmail.com')
        expect(settings[:port]).to eq(993)
        expect(settings[:user_name]).to eq('test@example.com')
        expect(settings[:password]).to eq('password123')
        expect(settings[:enable_ssl]).to be true
      end

      it 'merges custom IMAP settings from settings hash' do
        email_account = build(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"timeout":30,"debug":true}}'

        settings = email_account.imap_settings

        expect(settings['timeout']).to eq(30)
        expect(settings['debug']).to be true
      end

      it 'preserves base settings when merging custom settings' do
        email_account = build(:email_account,
          email: 'test@example.com',
          provider: 'gmail'
        )
        email_account.encrypted_settings = '{"imap":{"extra":"value"}}'

        settings = email_account.imap_settings

        expect(settings[:address]).to eq('imap.gmail.com')
        expect(settings[:port]).to eq(993)
        expect(settings['extra']).to eq('value')
      end
    end

    describe '#imap_server' do
      it 'returns correct server for gmail' do
        email_account = build(:email_account, provider: 'gmail')
        expect(email_account.imap_server).to eq('imap.gmail.com')
      end

      it 'returns correct server for outlook' do
        email_account = build(:email_account, provider: 'outlook')
        expect(email_account.imap_server).to eq('outlook.office365.com')
      end

      it 'returns correct server for yahoo' do
        email_account = build(:email_account, provider: 'yahoo')
        expect(email_account.imap_server).to eq('imap.mail.yahoo.com')
      end

      it 'returns custom server from settings for other providers' do
        email_account = build(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"server":"custom.mail.com"}}'
        expect(email_account.imap_server).to eq('custom.mail.com')
      end

      it 'returns localhost as default for unknown providers' do
        email_account = build(:email_account, provider: 'manual')
        email_account.encrypted_settings = '{}'
        expect(email_account.imap_server).to eq('localhost')
      end

      it 'returns localhost when settings are nil' do
        email_account = build(:email_account, provider: 'custom')
        email_account.encrypted_settings = nil
        expect(email_account.imap_server).to eq('localhost')
      end
    end

    describe '#imap_port' do
      it 'returns 993 for gmail' do
        email_account = build(:email_account, provider: 'gmail')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns 993 for outlook' do
        email_account = build(:email_account, provider: 'outlook')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns 993 for yahoo' do
        email_account = build(:email_account, provider: 'yahoo')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns custom port from settings for other providers' do
        email_account = build(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"port":143}}'
        expect(email_account.imap_port).to eq(143)
      end

      it 'returns 993 as default for unknown providers' do
        email_account = build(:email_account, provider: 'manual')
        email_account.encrypted_settings = '{}'
        expect(email_account.imap_port).to eq(993)
      end
    end

    describe '#password' do
      it 'returns encrypted_password value' do
        email_account = build(:email_account, encrypted_password: 'secret123')
        expect(email_account.password).to eq('secret123')
      end

      it 'acts as alias for encrypted_password' do
        email_account = build(:email_account, encrypted_password: 'password')
        expect(email_account.password).to eq(email_account.encrypted_password)
      end
    end

    describe '#oauth_configured?' do
      it 'returns true when access_token is present' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"token123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns true when refresh_token is present' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"oauth":{"refresh_token":"refresh123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns true when both tokens are present' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"token123","refresh_token":"refresh123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns false when no OAuth tokens are present' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"oauth":{}}'
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when oauth key is missing' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"other":"value"}'
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when settings are empty' do
        email_account = build(:email_account)
        email_account.encrypted_settings = nil
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when tokens are empty strings' do
        email_account = build(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"","refresh_token":""}}'
        expect(email_account.oauth_configured?).to be false
      end
    end
  end
end
