# frozen_string_literal: true

# Admin user model with secure authentication and role-based access control
class AdminUser < ApplicationRecord
  # Use Rails 8's built-in authentication generator patterns
  has_secure_password

  # Associations
  has_many :bulk_operations, foreign_key: :user_id, primary_key: :id

  # Constants
  MAX_FAILED_LOGIN_ATTEMPTS = 5
  LOCK_DURATION = 30.minutes
  SESSION_DURATION = 2.hours
  PASSWORD_MIN_LENGTH = 12

  # Enums
  enum :role, {
    read_only: 0,
    moderator: 1,
    admin: 2,
    super_admin: 3
  }, default: :read_only

  # Validations
  validates :email, presence: true,
                   uniqueness: { case_sensitive: false },
                   format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: PASSWORD_MIN_LENGTH },
                      format: {
                        with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&]).+\z/,
                        message: "must include uppercase, lowercase, number, and special character"
                      },
                      if: :password_digest_changed?

  # Callbacks
  before_save :downcase_email
  before_create :generate_session_token

  # Scopes
  scope :active, -> { where(locked_at: nil) }
  scope :locked, -> { where.not(locked_at: nil) }
  scope :with_expired_sessions, -> { where("session_expires_at < ?", Time.current) }

  # Class methods
  def self.authenticate(email, password)
    user = find_by(email: email.downcase)
    return nil unless user

    if user.locked?
      user.check_unlock_eligibility
      return nil if user.locked?
    end

    if user.authenticate(password)
      user.handle_successful_login
      user
    else
      user.handle_failed_login
      nil
    end
  end

  def self.find_by_valid_session(token)
    return nil if token.blank?

    user = find_by(session_token: token)
    return nil unless user
    return nil if user.session_expired?

    # Extend session on activity
    user.extend_session
    user
  end

  # Instance methods
  def locked?
    locked_at.present? && !unlock_eligible?
  end

  def unlock_eligible?
    locked_at.present? && locked_at < LOCK_DURATION.ago
  end

  def check_unlock_eligibility
    if unlock_eligible?
      unlock_account!
    end
  end

  def unlock_account!
    update!(
      locked_at: nil,
      failed_login_attempts: 0
    )
  end

  def lock_account!
    update!(
      locked_at: Time.current,
      session_token: nil,
      session_expires_at: nil
    )
  end

  def handle_successful_login
    update!(
      last_login_at: Time.current,
      failed_login_attempts: 0,
      locked_at: nil
    )
    regenerate_session_token
  end

  def handle_failed_login
    increment!(:failed_login_attempts)

    if failed_login_attempts >= MAX_FAILED_LOGIN_ATTEMPTS
      lock_account!
    end
  end

  def regenerate_session_token
    update!(
      session_token: generate_token,
      session_expires_at: SESSION_DURATION.from_now
    )
  end

  def extend_session
    update!(session_expires_at: SESSION_DURATION.from_now) if session_token.present?
  end

  def session_expired?
    session_expires_at.nil? || session_expires_at < Time.current
  end

  def invalidate_session!
    update!(
      session_token: nil,
      session_expires_at: nil
    )
  end

  def can_manage_patterns?
    admin? || super_admin? || moderator?
  end

  def can_edit_patterns?
    admin? || super_admin?
  end

  def can_delete_patterns?
    admin? || super_admin?
  end

  def can_import_patterns?
    super_admin?
  end

  def can_access_statistics?
    !read_only?
  end

  private

  def downcase_email
    self.email = email.downcase if email.present?
  end

  def generate_session_token
    self.session_token = generate_token
    self.session_expires_at = SESSION_DURATION.from_now
  end

  def generate_token
    SecureRandom.urlsafe_base64(32)
  end
end
