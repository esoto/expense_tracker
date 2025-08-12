require "digest"

class ApiToken < ApplicationRecord
  # Configuration constants
  TOKEN_LENGTH = 32
  CACHE_KEY_LENGTH = 16
  CACHE_EXPIRY = 1.minute
  attr_accessor :token

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :token_digest, presence: true, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }
  validate :expires_at_in_future, if: :expires_at?

  # Scopes
  scope :active, -> { where(active: true) }
  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :valid, -> { active.where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Callbacks
  before_validation :generate_token_if_blank, on: :create

  # Instance methods
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def valid_token?
    active? && !expired?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  def self.authenticate(token_string)
    return nil unless token_string.present?

    # Short-lived cache for successful authentications
    cache_key = "api_token:#{Digest::SHA256.hexdigest(token_string)[0..CACHE_KEY_LENGTH]}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
      # Use token_hash for quick lookup, then verify with BCrypt
      token_hash = Digest::SHA256.hexdigest(token_string)
      api_token = valid.find_by(token_hash: token_hash)

      # Verify the token using BCrypt comparison
      if api_token && BCrypt::Password.new(api_token.token_digest) == token_string
        api_token.touch_last_used!
        api_token
      else
        nil
      end
    end
  end

  def self.generate_secure_token
    SecureRandom.urlsafe_base64(TOKEN_LENGTH)
  end

  private

  def generate_token_if_blank
    return if token_digest.present?

    self.token = self.class.generate_secure_token
    self.token_digest = BCrypt::Password.create(token)
    # token_hash is used for quick lookups, not authentication
    self.token_hash = Digest::SHA256.hexdigest(token)
  end

  def expires_at_in_future
    return unless expires_at.present?

    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
  end
end
