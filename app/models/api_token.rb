class ApiToken < ApplicationRecord
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

    ApiToken.active.find_each do |api_token|
      if BCrypt::Password.new(api_token.token_digest) == token_string
        return api_token if api_token.valid_token?
      end
    end

    nil
  end

  def self.generate_secure_token
    SecureRandom.urlsafe_base64(32)
  end

  private

  def generate_token_if_blank
    return if token_digest.present?

    self.token = self.class.generate_secure_token
    self.token_digest = BCrypt::Password.create(token)
  end

  def expires_at_in_future
    return unless expires_at.present?

    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
  end
end
