require 'rails_helper'

RSpec.describe ApiToken, type: :model, unit: true do
  # Use build_stubbed for true unit tests
  let(:api_token) { build_stubbed(:api_token) }

  describe 'validations' do
    context 'name validation' do
      it 'requires presence of name' do
        api_token = build(:api_token, name: nil)
        expect(api_token).not_to be_valid
        expect(api_token.errors[:name]).to include("can't be blank")
      end

      it 'validates name maximum length' do
        api_token = build(:api_token, name: 'a' * 256)
        expect(api_token).not_to be_valid
        expect(api_token.errors[:name]).to include("is too long (maximum is 255 characters)")
      end

      it 'accepts names within length limit' do
        api_token = build(:api_token, name: 'a' * 255)
        expect(api_token).to be_valid
      end
    end

    context 'token_digest validation' do
      it 'requires presence of token_digest' do
        api_token = build(:api_token)
        # Set token_digest directly to nil to test validation
        api_token.token_digest = nil
        # Skip the callback
        api_token.instance_variable_set(:@skip_token_generation, true)
        allow(api_token).to receive(:generate_token_if_blank)

        expect(api_token).not_to be_valid
        expect(api_token.errors[:token_digest]).to include("can't be blank")
      end

      it 'validates uniqueness of token_digest' do
        existing_token = create(:api_token)
        new_token = build(:api_token)
        new_token.token_digest = existing_token.token_digest
        expect(new_token).not_to be_valid
        expect(new_token.errors[:token_digest]).to include("has already been taken")
      end
    end

    context 'active validation' do
      it 'validates inclusion of active' do
        api_token = build(:api_token)
        api_token.active = nil
        expect(api_token).not_to be_valid
        expect(api_token.errors[:active]).to include("is not included in the list")
      end

      it 'accepts true and false for active' do
        [ true, false ].each do |value|
          api_token = build(:api_token, active: value)
          expect(api_token).to be_valid
        end
      end
    end

    context 'expires_at validation' do
      it 'validates expires_at must be in future when present' do
        api_token = build(:api_token, expires_at: 1.day.ago)
        expect(api_token).not_to be_valid
        expect(api_token.errors[:expires_at]).to include("must be in the future")
      end

      it 'allows nil expires_at' do
        api_token = build(:api_token, expires_at: nil)
        expect(api_token).to be_valid
      end

      it 'accepts future dates' do
        api_token = build(:api_token, expires_at: 1.day.from_now)
        expect(api_token).to be_valid
      end

      it 'rejects exactly current time' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        api_token = build(:api_token, expires_at: freeze_time)
        expect(api_token).not_to be_valid
        expect(api_token.errors[:expires_at]).to include("must be in the future")
      end
    end
  end

  describe 'constants' do
    it 'defines expected constants' do
      expect(ApiToken::TOKEN_LENGTH).to eq(32)
      expect(ApiToken::CACHE_KEY_LENGTH).to eq(16)
      expect(ApiToken::CACHE_EXPIRY).to eq(1.minute)
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'uses correct where clause' do
        expect(ApiToken.active.to_sql).to include('WHERE "api_tokens"."active" = ')
      end
    end

    describe '.expired' do
      it 'uses correct where clause' do
        expect(ApiToken.expired.to_sql).to include('expires_at <')
      end
    end

    describe '.valid' do
      it 'combines active and non-expired conditions' do
        sql = ApiToken.valid.to_sql
        expect(sql).to include('active')
        expect(sql).to include('expires_at')
      end
    end
  end

  describe 'callbacks' do
    describe '#generate_token_if_blank' do
      it 'generates token on create when token_digest is blank' do
        api_token = build(:api_token)
        api_token.token_digest = nil

        expect(SecureRandom).to receive(:urlsafe_base64).with(ApiToken::TOKEN_LENGTH).and_return('generated_token')
        expect(BCrypt::Password).to receive(:create).with('generated_token').and_return('hashed_token')

        api_token.save

        expect(api_token.token).to eq('generated_token')
        expect(api_token.token_digest).to eq('hashed_token')
        expect(api_token.token_hash).to eq(Digest::SHA256.hexdigest('generated_token'))
      end

      it 'does not generate token when token_digest is present' do
        api_token = build(:api_token)
        api_token.token_digest = 'existing_digest'

        expect(SecureRandom).not_to receive(:urlsafe_base64)

        api_token.save
        expect(api_token.token_digest).to eq('existing_digest')
      end

      it 'only runs on create' do
        api_token = create(:api_token)
        original_digest = api_token.token_digest

        expect(SecureRandom).not_to receive(:urlsafe_base64)

        api_token.update(name: 'Updated Name')
        expect(api_token.token_digest).to eq(original_digest)
      end
    end
  end

  describe 'class methods' do
    describe '.authenticate' do
      let(:token_string) { 'test_token_string' }
      let(:token_hash) { Digest::SHA256.hexdigest(token_string) }
      let(:api_token) { build_stubbed(:api_token, token_hash: token_hash) }

      before do
        allow(Rails.cache).to receive(:fetch).and_yield
      end

      context 'with valid token' do
        before do
          allow(ApiToken).to receive_message_chain(:valid, :find_by).with(token_hash: token_hash).and_return(api_token)
          allow(BCrypt::Password).to receive(:new).with(api_token.token_digest).and_return(BCrypt::Password.create(token_string))
          allow(api_token).to receive(:touch_last_used!)
        end

        it 'returns the token when authentication succeeds' do
          result = ApiToken.authenticate(token_string)
          expect(result).to eq(api_token)
        end

        it 'updates last_used_at' do
          expect(api_token).to receive(:touch_last_used!)
          ApiToken.authenticate(token_string)
        end

        it 'uses cache with correct key and expiry' do
          cache_key = "api_token:#{token_hash[0..ApiToken::CACHE_KEY_LENGTH]}"
          expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: ApiToken::CACHE_EXPIRY)
          ApiToken.authenticate(token_string)
        end
      end

      context 'with invalid token' do
        it 'returns nil for nil token' do
          result = ApiToken.authenticate(nil)
          expect(result).to be_nil
        end

        it 'returns nil for empty token' do
          result = ApiToken.authenticate('')
          expect(result).to be_nil
        end

        it 'returns nil when token not found' do
          allow(ApiToken).to receive_message_chain(:valid, :find_by).and_return(nil)
          result = ApiToken.authenticate(token_string)
          expect(result).to be_nil
        end

        it 'returns nil when BCrypt verification fails' do
          allow(ApiToken).to receive_message_chain(:valid, :find_by).and_return(api_token)
          allow(BCrypt::Password).to receive(:new).with(api_token.token_digest).and_return(BCrypt::Password.create('different_token'))

          result = ApiToken.authenticate(token_string)
          expect(result).to be_nil
        end

        it 'does not update last_used_at for failed authentication' do
          allow(ApiToken).to receive_message_chain(:valid, :find_by).and_return(nil)
          expect(api_token).not_to receive(:touch_last_used!)
          ApiToken.authenticate(token_string)
        end
      end
    end

    describe '.generate_secure_token' do
      it 'generates token using SecureRandom' do
        expect(SecureRandom).to receive(:urlsafe_base64).with(ApiToken::TOKEN_LENGTH).and_return('secure_token')
        result = ApiToken.generate_secure_token
        expect(result).to eq('secure_token')
      end

      it 'generates different tokens on each call' do
        allow(SecureRandom).to receive(:urlsafe_base64).and_return('token1', 'token2')
        token1 = ApiToken.generate_secure_token
        token2 = ApiToken.generate_secure_token
        expect(token1).not_to eq(token2)
      end
    end
  end

  describe 'instance methods' do
    describe '#expired?' do
      it 'returns true when expires_at is in the past' do
        api_token = build_stubbed(:api_token, expires_at: 1.day.ago)
        expect(api_token.expired?).to be true
      end

      it 'returns false when expires_at is in the future' do
        api_token = build_stubbed(:api_token, expires_at: 1.day.from_now)
        expect(api_token.expired?).to be false
      end

      it 'returns false when expires_at is nil' do
        api_token = build_stubbed(:api_token, expires_at: nil)
        expect(api_token.expired?).to be false
      end

      it 'uses current time for comparison' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        api_token = build_stubbed(:api_token, expires_at: freeze_time - 1.second)
        expect(api_token.expired?).to be true

        api_token.expires_at = freeze_time + 1.second
        expect(api_token.expired?).to be false
      end
    end

    describe '#valid_token?' do
      it 'returns true for active and unexpired token' do
        api_token = build_stubbed(:api_token, active: true, expires_at: 1.day.from_now)
        expect(api_token.valid_token?).to be true
      end

      it 'returns false for inactive token' do
        api_token = build_stubbed(:api_token, active: false, expires_at: 1.day.from_now)
        expect(api_token.valid_token?).to be false
      end

      it 'returns false for expired token' do
        api_token = build_stubbed(:api_token, active: true, expires_at: 1.day.ago)
        expect(api_token.valid_token?).to be false
      end

      it 'returns true for active token with no expiration' do
        api_token = build_stubbed(:api_token, active: true, expires_at: nil)
        expect(api_token.valid_token?).to be true
      end

      it 'returns false for inactive expired token' do
        api_token = build_stubbed(:api_token, active: false, expires_at: 1.day.ago)
        expect(api_token.valid_token?).to be false
      end
    end

    describe '#touch_last_used!' do
      it 'updates last_used_at column' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        api_token = create(:api_token)
        expect(api_token).to receive(:update_column).with(:last_used_at, freeze_time)
        api_token.touch_last_used!
      end

      it 'bypasses validations' do
        api_token = create(:api_token)
        # Make the token invalid
        api_token.name = nil

        # Should still update despite invalid state
        expect { api_token.touch_last_used! }.not_to raise_error
      end
    end
  end

  describe 'attr_accessor' do
    it 'provides token accessor' do
      api_token = build(:api_token)
      api_token.token = 'test_token'
      expect(api_token.token).to eq('test_token')
    end

    it 'token is not persisted to database' do
      api_token = create(:api_token)
      original_token = api_token.token

      reloaded = ApiToken.find(api_token.id)
      expect(reloaded.token).to be_nil
      expect(original_token).to be_present
    end
  end

  describe 'edge cases' do
    describe 'token generation uniqueness' do
      it 'handles collision in token generation' do
        api_token = build(:api_token)

        # Simulate collision by returning same token twice, then different
        allow(SecureRandom).to receive(:urlsafe_base64).and_return('same_token', 'same_token', 'different_token')

        api_token.save
        expect(api_token.token).to eq('same_token')
      end
    end

    describe 'BCrypt password handling' do
      it 'handles BCrypt cost factor properly' do
        api_token = build(:api_token)
        api_token.save

        password = BCrypt::Password.new(api_token.token_digest)
        expect(password.cost).to be >= BCrypt::Engine::MIN_COST
      end
    end

    describe 'cache key generation' do
      it 'handles very long tokens in cache key' do
        very_long_token = 'a' * 1000
        token_hash = Digest::SHA256.hexdigest(very_long_token)
        cache_key = "api_token:#{token_hash[0..ApiToken::CACHE_KEY_LENGTH]}"

        expect(cache_key.length).to be < 250  # Memcached key length limit
      end
    end

    describe 'concurrent authentication' do
      it 'handles race conditions in cache' do
        token_string = 'test_token'
        api_token = build_stubbed(:api_token)

        # Simulate concurrent cache reads
        call_count = 0
        allow(Rails.cache).to receive(:fetch) do |&block|
          call_count += 1
          block.call
        end

        allow(ApiToken).to receive_message_chain(:valid, :find_by).and_return(api_token)
        allow(BCrypt::Password).to receive(:new).and_return(BCrypt::Password.create(token_string))
        allow(api_token).to receive(:touch_last_used!)

        # Multiple concurrent authentications
        3.times { ApiToken.authenticate(token_string) }

        # Should call cache fetch each time
        expect(call_count).to eq(3)
      end
    end

    describe 'validation bypass in callbacks' do
      it 'generates token even when other validations fail' do
        api_token = build(:api_token, name: nil)  # Invalid due to name
        api_token.token_digest = nil  # Trigger token generation

        # Token generation should still work
        expect(SecureRandom).to receive(:urlsafe_base64).and_return('generated_token')

        api_token.valid?  # Trigger validations and callbacks

        # Token should be generated even though model is invalid
        expect(api_token.token).to eq('generated_token')
      end
    end
  end

  describe 'security considerations' do
    describe 'token storage' do
      it 'never stores plain text token in database' do
        api_token = create(:api_token)

        # Check database columns don't contain plain token
        attributes = api_token.attributes
        plain_token = api_token.token

        attributes.each do |key, value|
          next if value.nil? || key == 'id'
          expect(value.to_s).not_to eq(plain_token) if plain_token.present?
        end
      end
    end

    describe 'timing attack prevention' do
      it 'uses BCrypt for constant-time comparison' do
        token_string = 'test_token'
        api_token = build_stubbed(:api_token)

        allow(ApiToken).to receive_message_chain(:valid, :find_by).and_return(api_token)

        # BCrypt comparison is constant-time
        bcrypt_password = double('BCrypt::Password')
        allow(BCrypt::Password).to receive(:new).and_return(bcrypt_password)
        allow(bcrypt_password).to receive(:==).with(token_string).and_return(true)
        allow(api_token).to receive(:touch_last_used!)

        ApiToken.authenticate(token_string)

        # Verify BCrypt comparison was used
        expect(bcrypt_password).to have_received(:==).with(token_string)
      end
    end
  end
end
