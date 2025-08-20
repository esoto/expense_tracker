require 'rails_helper'

RSpec.describe EmailAccount, type: :model, unit: true do
  # Use build_stubbed for true unit tests
  let(:email_account) { build_stubbed(:email_account) }

  describe 'validations' do
    context 'email validation' do
      it 'requires presence of email' do
        email_account = build(:email_account, email: nil)
        expect(email_account).not_to be_valid
        expect(email_account.errors[:email]).to include("can't be blank")
      end

      it 'validates email format with URI::MailTo::EMAIL_REGEXP' do
        invalid_emails = ['invalid', 'invalid@', '@example.com', 'user@', 'user space@example.com', 'user@.com']
        invalid_emails.each do |invalid_email|
          email_account = build(:email_account, email: invalid_email)
          expect(email_account).not_to be_valid
          expect(email_account.errors[:email]).to include("is invalid")
        end
      end

      it 'accepts valid email formats' do
        valid_emails = [
          'user@example.com', 
          'user.name@example.co.uk', 
          'user+tag@example.org',
          'user_name@example-domain.com',
          '123@example.com'
        ]
        valid_emails.each do |valid_email|
          email_account = build(:email_account, email: valid_email)
          expect(email_account).to be_valid, "Email '#{valid_email}' should be valid"
        end
      end

      it 'validates email uniqueness' do
        existing_account = create(:email_account, email: 'test@example.com')
        new_account = build(:email_account, email: 'test@example.com')
        expect(new_account).not_to be_valid
        expect(new_account.errors[:email]).to include("has already been taken")
      end

      it 'validates email uniqueness case-sensitively' do
        existing_account = create(:email_account, email: 'test@example.com')
        new_account = build(:email_account, email: 'TEST@EXAMPLE.COM')
        # Email uniqueness in Rails is case-sensitive by default
        expect(new_account).to be_valid
      end
    end

    context 'provider validation' do
      it 'requires presence of provider' do
        email_account = build(:email_account, provider: nil)
        expect(email_account).not_to be_valid
        expect(email_account.errors[:provider]).to include("can't be blank")
      end

      it 'validates provider inclusion' do
        valid_providers = ['gmail', 'outlook', 'yahoo', 'custom', 'manual']
        valid_providers.each do |provider|
          email_account = build(:email_account, provider: provider)
          expect(email_account).to be_valid, "Provider '#{provider}' should be valid"
        end
      end

      it 'rejects invalid providers' do
        invalid_providers = ['hotmail', 'aol', 'protonmail', '']
        invalid_providers.each do |provider|
          email_account = build(:email_account, provider: provider)
          expect(email_account).not_to be_valid
          expect(email_account.errors[:provider]).to include("is not included in the list")
        end
      end
    end

    context 'bank_name validation' do
      it 'requires presence of bank_name' do
        email_account = build(:email_account, bank_name: nil)
        expect(email_account).not_to be_valid
        expect(email_account.errors[:bank_name]).to include("can't be blank")
      end

      it 'accepts any non-empty bank name' do
        bank_names = ['BCR', 'BAC', 'Custom Bank', 'International Bank', '123 Bank']
        bank_names.each do |bank_name|
          email_account = build(:email_account, bank_name: bank_name)
          expect(email_account).to be_valid, "Bank name '#{bank_name}' should be valid"
        end
      end
    end

    context 'active validation' do
      it 'validates active as boolean' do
        [true, false].each do |value|
          email_account = build(:email_account, active: value)
          expect(email_account).to be_valid
        end
      end

      it 'rejects non-boolean values for active' do
        email_account = build(:email_account)
        email_account.active = nil
        expect(email_account).not_to be_valid
        expect(email_account.errors[:active]).to include("is not included in the list")
      end
    end
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

  describe 'associations' do
    it 'defines has_many expenses with destroy dependency' do
      association = EmailAccount.reflect_on_association(:expenses)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it 'defines has_many budgets with destroy dependency' do
      association = EmailAccount.reflect_on_association(:budgets)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it 'defines has_many parsing_rules with custom keys' do
      association = EmailAccount.reflect_on_association(:parsing_rules)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:primary_key]).to eq(:bank_name)
      expect(association.options[:foreign_key]).to eq(:bank_name)
    end

    it 'defines has_many sync_session_accounts' do
      association = EmailAccount.reflect_on_association(:sync_session_accounts)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it 'defines has_many sync_sessions through sync_session_accounts' do
      association = EmailAccount.reflect_on_association(:sync_sessions)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:through]).to eq(:sync_session_accounts)
    end

    it 'defines has_many categories through expenses' do
      association = EmailAccount.reflect_on_association(:categories)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:through]).to eq(:expenses)
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
    it 'declares encrypted_password as encrypted' do
      expect(EmailAccount.encrypted_attributes).to include(:encrypted_password)
    end

    it 'declares encrypted_settings as encrypted' do
      expect(EmailAccount.encrypted_attributes).to include(:encrypted_settings)
    end
  end

  describe 'instance methods' do
    describe '#display_name' do
      it 'returns email and bank name formatted' do
        email_account = build_stubbed(:email_account, email: 'test@example.com', bank_name: 'BAC')
        expect(email_account.display_name).to eq('test@example.com (BAC)')
      end

      it 'handles special characters in bank name' do
        email_account = build_stubbed(:email_account, email: 'test@example.com', bank_name: 'Bank & Trust')
        expect(email_account.display_name).to eq('test@example.com (Bank & Trust)')
      end
    end

    describe '#settings' do
      it 'returns empty hash when encrypted_settings is nil' do
        email_account = build_stubbed(:email_account, encrypted_settings: nil)
        expect(email_account.settings).to eq({})
      end

      it 'returns empty hash when encrypted_settings is empty' do
        email_account = build_stubbed(:email_account, encrypted_settings: '')
        expect(email_account.settings).to eq({})
      end

      it 'parses valid JSON from encrypted_settings' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"key":"value","nested":{"key2":"value2"}}'
        expect(email_account.settings).to eq({'key' => 'value', 'nested' => {'key2' => 'value2'}})
      end

      it 'returns empty hash for invalid JSON' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = 'invalid json {'
        expect(email_account.settings).to eq({})
      end

      it 'handles JSON parse errors gracefully' do
        email_account = build_stubbed(:email_account)
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError)
        expect(email_account.settings).to eq({})
      end
    end

    describe '#settings=' do
      it 'converts hash to JSON string' do
        email_account = build_stubbed(:email_account)
        settings_hash = {'key' => 'value', 'number' => 123}
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end

      it 'handles nested hashes' do
        email_account = build_stubbed(:email_account)
        settings_hash = {'imap' => {'server' => 'example.com', 'port' => 993}}
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end

      it 'handles empty hash' do
        email_account = build_stubbed(:email_account)
        email_account.settings = {}
        expect(email_account.encrypted_settings).to eq('{}')
      end

      it 'handles arrays in settings' do
        email_account = build_stubbed(:email_account)
        settings_hash = {'folders' => ['INBOX', 'Sent'], 'flags' => []}
        email_account.settings = settings_hash
        expect(email_account.encrypted_settings).to eq(settings_hash.to_json)
      end
    end

    describe '#imap_settings' do
      it 'builds base settings with correct structure' do
        email_account = build_stubbed(:email_account, 
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
        email_account = build_stubbed(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"timeout":30,"debug":true}}'
        
        settings = email_account.imap_settings
        
        expect(settings['timeout']).to eq(30)
        expect(settings['debug']).to be true
      end

      it 'preserves base settings when merging custom settings' do
        email_account = build_stubbed(:email_account, 
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
        email_account = build_stubbed(:email_account, provider: 'gmail')
        expect(email_account.imap_server).to eq('imap.gmail.com')
      end

      it 'returns correct server for outlook' do
        email_account = build_stubbed(:email_account, provider: 'outlook')
        expect(email_account.imap_server).to eq('outlook.office365.com')
      end

      it 'returns correct server for yahoo' do
        email_account = build_stubbed(:email_account, provider: 'yahoo')
        expect(email_account.imap_server).to eq('imap.mail.yahoo.com')
      end

      it 'returns custom server from settings for other providers' do
        email_account = build_stubbed(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"server":"custom.mail.com"}}'
        expect(email_account.imap_server).to eq('custom.mail.com')
      end

      it 'returns localhost as default for unknown providers' do
        email_account = build_stubbed(:email_account, provider: 'manual')
        email_account.encrypted_settings = '{}'
        expect(email_account.imap_server).to eq('localhost')
      end

      it 'returns localhost when settings are nil' do
        email_account = build_stubbed(:email_account, provider: 'custom')
        email_account.encrypted_settings = nil
        expect(email_account.imap_server).to eq('localhost')
      end
    end

    describe '#imap_port' do
      it 'returns 993 for gmail' do
        email_account = build_stubbed(:email_account, provider: 'gmail')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns 993 for outlook' do
        email_account = build_stubbed(:email_account, provider: 'outlook')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns 993 for yahoo' do
        email_account = build_stubbed(:email_account, provider: 'yahoo')
        expect(email_account.imap_port).to eq(993)
      end

      it 'returns custom port from settings for other providers' do
        email_account = build_stubbed(:email_account, provider: 'custom')
        email_account.encrypted_settings = '{"imap":{"port":143}}'
        expect(email_account.imap_port).to eq(143)
      end

      it 'returns 993 as default for unknown providers' do
        email_account = build_stubbed(:email_account, provider: 'manual')
        email_account.encrypted_settings = '{}'
        expect(email_account.imap_port).to eq(993)
      end
    end

    describe '#password' do
      it 'returns encrypted_password value' do
        email_account = build_stubbed(:email_account, encrypted_password: 'secret123')
        expect(email_account.password).to eq('secret123')
      end

      it 'acts as alias for encrypted_password' do
        email_account = build_stubbed(:email_account, encrypted_password: 'password')
        expect(email_account.password).to eq(email_account.encrypted_password)
      end
    end

    describe '#oauth_configured?' do
      it 'returns true when access_token is present' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"token123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns true when refresh_token is present' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"oauth":{"refresh_token":"refresh123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns true when both tokens are present' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"token123","refresh_token":"refresh123"}}'
        expect(email_account.oauth_configured?).to be true
      end

      it 'returns false when no OAuth tokens are present' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"oauth":{}}'
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when oauth key is missing' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"other":"value"}'
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when settings are empty' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = nil
        expect(email_account.oauth_configured?).to be false
      end

      it 'returns false when tokens are empty strings' do
        email_account = build_stubbed(:email_account)
        email_account.encrypted_settings = '{"oauth":{"access_token":"","refresh_token":""}}'
        expect(email_account.oauth_configured?).to be false
      end
    end
  end

  describe 'edge cases' do
    describe 'provider-specific behavior' do
      it 'handles case-sensitive provider names' do
        # Provider should be stored as lowercase
        email_account = build(:email_account, provider: 'gmail')
        expect(email_account).to be_valid
        
        # But uppercase should be invalid
        email_account.provider = 'GMAIL'
        expect(email_account).not_to be_valid
      end
    end

    describe 'settings edge cases' do
      it 'handles deeply nested settings' do
        email_account = build_stubbed(:email_account)
        deep_settings = {
          'level1' => {
            'level2' => {
              'level3' => {
                'level4' => 'value'
              }
            }
          }
        }
        email_account.settings = deep_settings
        expect(JSON.parse(email_account.encrypted_settings)).to eq(deep_settings)
      end

      it 'handles non-serializable objects in settings' do
        email_account = build_stubbed(:email_account)
        # Objects like models typically can't be serialized to JSON
        settings = {'object' => Object.new}
        # to_json doesn't raise errors, it serializes objects with their class name
        expect { email_account.settings = settings }.not_to raise_error
        expect(email_account.encrypted_settings).to be_a(String)
      end

      it 'handles very large settings hash' do
        email_account = build_stubbed(:email_account)
        large_settings = {}
        1000.times { |i| large_settings["key_#{i}"] = "value_#{i}" }
        
        email_account.settings = large_settings
        parsed = JSON.parse(email_account.encrypted_settings)
        expect(parsed.keys.size).to eq(1000)
      end
    end

    describe 'password edge cases' do
      it 'handles nil encrypted_password' do
        email_account = build_stubbed(:email_account, encrypted_password: nil)
        expect(email_account.password).to be_nil
      end

      it 'handles empty encrypted_password' do
        email_account = build_stubbed(:email_account, encrypted_password: '')
        expect(email_account.password).to eq('')
      end

      it 'preserves special characters in password' do
        special_password = 'P@$$w0rd!#$%^&*()'
        email_account = build_stubbed(:email_account, encrypted_password: special_password)
        expect(email_account.password).to eq(special_password)
      end
    end

    describe 'bank_name edge cases' do
      it 'handles bank names with special characters' do
        email_account = build(:email_account, bank_name: 'Bank & Trust Co.')
        expect(email_account).to be_valid
      end

      it 'handles very long bank names' do
        # No length validation on bank_name
        long_name = 'A' * 500
        email_account = build(:email_account, bank_name: long_name)
        expect(email_account).to be_valid
      end

      it 'rejects empty string bank_name' do
        email_account = build(:email_account, bank_name: '')
        expect(email_account).not_to be_valid
      end
    end

    describe 'concurrent access' do
      it 'handles concurrent settings updates' do
        email_account = create(:email_account)
        
        threads = 5.times.map do |i|
          Thread.new do
            account = EmailAccount.find(email_account.id)
            account.settings = {"thread_#{i}" => "value_#{i}"}
            account.save
          end
        end
        
        threads.each(&:join)
        
        # Last write wins
        email_account.reload
        expect(email_account.settings).to be_a(Hash)
      end
    end
  end

  describe 'security considerations' do
    describe 'password handling' do
      it 'does not expose password in inspect' do
        email_account = build_stubbed(:email_account, encrypted_password: 'secret')
        inspection = email_account.inspect
        
        # Rails encrypts attributes should filter the password
        expect(inspection).not_to include('secret')
      end
    end

    describe 'settings security' do
      it 'encrypts sensitive settings' do
        email_account = create(:email_account)
        sensitive_settings = {'oauth' => {'access_token' => 'secret_token'}}
        email_account.settings = sensitive_settings
        email_account.save
        
        # Direct database value should be encrypted
        raw_value = email_account.read_attribute_before_type_cast(:encrypted_settings)
        expect(raw_value).not_to include('secret_token')
      end
    end
  end
end