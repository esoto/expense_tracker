require 'rails_helper'

RSpec.describe ApiToken, type: :model do
  describe 'validations' do
    let!(:token) { create(:api_token, name: 'Test Token', expires_at: 1.year.from_now, active: true) }

    it 'is valid with valid attributes' do
      expect(token).to be_valid
    end
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:token_digest) }

    it 'validates expires_at is in the future' do
      token = build(:api_token, name: 'Test', expires_at: 1.day.ago)
      expect(token).not_to be_valid
      expect(token.errors[:expires_at]).to include('must be in the future')
    end

    it 'allows nil expires_at' do
      token = build(:api_token, name: 'Test', expires_at: nil)
      expect(token).to be_valid
    end

    it 'validates active as boolean' do
      token = build(:api_token, name: 'Test', expires_at: 1.year.from_now, active: nil)
      expect(token).not_to be_valid
      expect(token.errors[:active]).to include('is not included in the list')
    end
  end

  describe 'scopes' do
    let!(:active_token) { create(:api_token, name: 'Active Token', expires_at: 1.year.from_now, active: true) }
    let!(:inactive_token) { create(:api_token, name: 'Inactive Token', expires_at: 1.year.from_now, active: false) }
    let!(:expired_token) { create(:api_token, name: 'Expired Token', expires_at: 1.day.from_now, active: true) }

    it 'returns active tokens' do
      expect(ApiToken.active).to include(active_token)
      expect(ApiToken.active).not_to include(inactive_token)
    end

    it 'returns valid tokens (active and unexpired)' do
      expect(ApiToken.valid).to include(active_token)
      expect(ApiToken.valid).not_to include(inactive_token)
    end
  end

  describe 'callbacks' do
    it 'generates token on creation' do
      token = create(:api_token, name: 'Test Token', expires_at: 1.year.from_now)
      expect(token.token).to be_present
      expect(token.token_digest).to be_present
    end

    it 'does not regenerate token if already present' do
      token = create(:api_token, name: 'Test Token', expires_at: 1.year.from_now)
      original_token = token.token
      original_digest = token.token_digest

      token.save!

      expect(token.token).to eq(original_token)
      expect(token.token_digest).to eq(original_digest)
    end
  end

  describe '.authenticate' do
    let!(:valid_token) { create(:api_token, name: 'Valid Token', expires_at: 1.year.from_now, active: true) }
    let!(:inactive_token) { create(:api_token, name: 'Inactive Token', expires_at: 1.year.from_now, active: false) }

    it 'authenticates valid active token' do
      result = ApiToken.authenticate(valid_token.token)
      expect(result).to eq(valid_token)
    end

    it 'rejects inactive token' do
      result = ApiToken.authenticate(inactive_token.token)
      expect(result).to be_nil
    end

    it 'rejects expired token' do
      # Create expired token by manually setting the timestamp
      expired_token = create(:api_token, name: 'Expired Token', expires_at: 1.year.from_now, active: true)
      expired_token.update_column(:expires_at, 1.day.ago)

      result = ApiToken.authenticate(expired_token.token)
      expect(result).to be_nil
    end

    it 'rejects invalid token' do
      result = ApiToken.authenticate('invalid-token')
      expect(result).to be_nil
    end

    it 'rejects nil token' do
      result = ApiToken.authenticate(nil)
      expect(result).to be_nil
    end

    it 'rejects empty token' do
      result = ApiToken.authenticate('')
      expect(result).to be_nil
    end
  end

  describe '#valid_token?' do
    it 'returns true for active unexpired token' do
      token = create(:api_token, name: 'Valid Token', expires_at: 1.year.from_now, active: true)
      expect(token).to be_valid_token
    end

    it 'returns false for inactive token' do
      token = create(:api_token, name: 'Inactive Token', expires_at: 1.year.from_now, active: false)
      expect(token).not_to be_valid_token
    end

    it 'returns false for expired token' do
      token = create(:api_token, name: 'Expired Token', expires_at: 1.year.from_now, active: true)
      token.update_column(:expires_at, 1.day.ago)
      expect(token).not_to be_valid_token
    end

    it 'returns true for active token with no expiration' do
      token = create(:api_token, name: 'Permanent Token', expires_at: nil, active: true)
      expect(token).to be_valid_token
    end
  end

  describe '#expired?' do
    it 'returns true for expired token' do
      token = create(:api_token, name: 'Expired Token', expires_at: 1.year.from_now, active: true)
      token.update_column(:expires_at, 1.day.ago)
      expect(token).to be_expired
    end

    it 'returns false for unexpired token' do
      token = create(:api_token, name: 'Valid Token', expires_at: 1.year.from_now, active: true)
      expect(token).not_to be_expired
    end

    it 'returns false for token with no expiration' do
      token = create(:api_token, name: 'Permanent Token', expires_at: nil, active: true)
      expect(token).not_to be_expired
    end
  end

  describe '.generate_secure_token' do
    it 'generates unique tokens' do
      token1 = ApiToken.generate_secure_token
      token2 = ApiToken.generate_secure_token

      expect(token1).not_to eq(token2)
      expect(token1.length).to be >= 32
      expect(token2.length).to be >= 32
    end
  end

  describe 'token security' do
    let(:token) { create(:api_token, name: 'Security Test', expires_at: 1.year.from_now) }

    it 'stores hashed token digest' do
      expect(token.token_digest).to be_present
      expect(token.token_digest).not_to eq(token.token)
    end

    it 'can verify token against digest' do
      password = BCrypt::Password.new(token.token_digest)
      expect(password).to eq(token.token)
    end

    it 'stores token in memory during creation' do
      original_token = token.token
      expect(original_token).to be_present

      # Token is only available in memory, not persisted
      reloaded_token = ApiToken.find(token.id)
      expect(reloaded_token.token).to be_nil
    end
  end

  describe 'additional methods' do
    it 'can touch last_used timestamp' do
      token = create(:api_token, name: 'Test Token', expires_at: 1.year.from_now, active: true)
      expect(token.last_used_at).to be_nil

      token.touch_last_used!
      expect(token.last_used_at).to be_present
    end

    it 'has proper attribute accessors' do
      token = build(:api_token, name: 'Test', expires_at: 1.year.from_now)
      token.token = 'test-token'
      expect(token.token).to eq('test-token')
    end
  end

  describe 'expired scope' do
    let!(:expired_token) { create(:api_token, :expired) }
    let!(:valid_token) { create(:api_token) }

    it 'returns only expired tokens' do
      expect(ApiToken.expired).to include(expired_token)
      expect(ApiToken.expired).not_to include(valid_token)
    end
  end

  describe 'edge cases and validations' do
    it 'validates name length maximum' do
      long_name = 'a' * 256
      token = build(:api_token, name: long_name)
      expect(token).not_to be_valid
      expect(token.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'handles token creation when token_digest already exists' do
      token = build(:api_token)
      token.token_digest = 'existing_digest'
      token.save!
      expect(token.token_digest).to eq('existing_digest')
    end

    it 'handles very long token strings in authenticate' do
      very_long_token = 'a' * 1000
      result = ApiToken.authenticate(very_long_token)
      expect(result).to be_nil
    end

    it 'validates expires_at only when present during validation' do
      token = build(:api_token, expires_at: nil)
      expect(token).to be_valid
      
      token.expires_at = 1.hour.from_now
      expect(token).to be_valid
    end

    it 'handles authentication with multiple tokens having same name' do
      token1 = create(:api_token, name: 'Same Name')
      token2 = create(:api_token, name: 'Same Name')
      
      result1 = ApiToken.authenticate(token1.token)
      result2 = ApiToken.authenticate(token2.token)
      
      expect(result1).to eq(token1)
      expect(result2).to eq(token2)
    end
  end

  describe 'callback edge cases' do
    it 'does not generate token when updating existing record' do
      token = create(:api_token)
      original_digest = token.token_digest
      
      token.update!(name: 'Updated Name')
      expect(token.token_digest).to eq(original_digest)
    end

    it 'generates token even when token is manually set to nil before validation' do
      token = build(:api_token)
      token.token = nil
      token.save!
      
      expect(token.token).to be_present
      expect(token.token_digest).to be_present
    end
  end
end
