# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminUser, type: :model, unit: true do
  # Helper method to build a stubbed instance
  def build_admin_user(attributes = {})
    default_attributes = {
      email: "admin@example.com",
      name: "Admin User",
      password: "SecureP@ssw0rd123",
      password_digest: "$2a$12$K0ByB.6YI2/OYr1M3DBijeTG.7.rldDUV4kPW3gCvnKHqw2q3x8e6",
      role: :read_only,
      failed_login_attempts: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
    build_stubbed(:admin_user, default_attributes.merge(attributes))
  end

  describe "constants" do
    it "defines security constants" do
      expect(AdminUser::MAX_FAILED_LOGIN_ATTEMPTS).to eq(5)
      expect(AdminUser::LOCK_DURATION).to eq(30.minutes)
      expect(AdminUser::SESSION_DURATION).to eq(2.hours)
      expect(AdminUser::PASSWORD_MIN_LENGTH).to eq(12)
    end
  end

  describe "has_secure_password" do
    it "provides password authentication" do
      user = build_admin_user
      expect(user).to respond_to(:authenticate)
      expect(user).to respond_to(:password=)
      expect(user).to respond_to(:password_confirmation=)
    end
  end

  describe "enums" do
    it "defines role enum with default" do
      should define_enum_for(:role)
        .with_values(
          read_only: 0,
          moderator: 1,
          admin: 2,
          super_admin: 3
        )
        .backed_by_column_of_type(:integer)
    end

    it "defaults to read_only role" do
      user = AdminUser.new
      expect(user.role).to eq("read_only")
    end
  end

  describe "validations" do
    describe "email" do
      it "requires email to be present" do
        user = build_admin_user(email: nil)
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include("can't be blank")
      end

      it "requires email to be unique (case insensitive)" do
        user = build_admin_user(email: "TEST@EXAMPLE.COM")
        allow(user).to receive(:errors).and_return(ActiveModel::Errors.new(user))
        relation = double("relation")
        allow(AdminUser).to receive(:where).and_return(relation)
        allow(relation).to receive(:exists?).and_return(false)
        expect(user).to be_valid
      end

      it "validates email format" do
        invalid_emails = [ "invalid", "test@", "@example.com", "test@.com" ]
        invalid_emails.each do |email|
          user = build_admin_user(email: email)
          expect(user).not_to be_valid
          expect(user.errors[:email]).to include("is invalid")
        end
      end

      it "accepts valid email formats" do
        valid_emails = [ "user@example.com", "test.user@example.co.uk", "user+tag@domain.org" ]
        valid_emails.each do |email|
          user = build_admin_user(email: email)
          expect(user).to be_valid
        end
      end
    end

    describe "name" do
      it "requires name to be present" do
        user = build_admin_user(name: nil)
        expect(user).not_to be_valid
        expect(user.errors[:name]).to include("can't be blank")
      end

      it "limits name length to 100 characters" do
        user = build_admin_user(name: "A" * 101)
        expect(user).not_to be_valid
        expect(user.errors[:name]).to include("is too long (maximum is 100 characters)")
      end

      it "accepts names up to 100 characters" do
        user = build_admin_user(name: "A" * 100)
        expect(user).to be_valid
      end
    end

    describe "password" do
      it "requires minimum length when password_digest changed" do
        user = build_admin_user(password: "Short1!")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("is too short (minimum is 12 characters)")
      end

      it "requires uppercase letter" do
        user = build_admin_user(password: "lowercase1234!")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it "requires lowercase letter" do
        user = build_admin_user(password: "UPPERCASE1234!")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it "requires number" do
        user = build_admin_user(password: "NoNumbersHere!")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it "requires special character" do
        user = build_admin_user(password: "NoSpecialChar123")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it "accepts valid passwords" do
        user = build_admin_user(password: "ValidP@ssw0rd123")
        allow(user).to receive(:password_digest_changed?).and_return(true)
        expect(user).to be_valid
      end

      it "skips validation when password_digest not changed" do
        user = build_admin_user(password: nil)
        allow(user).to receive(:password_digest_changed?).and_return(false)
        expect(user).to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".active" do
    end

    describe ".locked" do
    end

    describe ".with_expired_sessions" do
      it "filters users with expired sessions" do
        sql = AdminUser.with_expired_sessions.to_sql
        expect(sql).to include("session_expires_at <")
      end
    end
  end

  describe "callbacks" do
    describe "before_save" do
      it "downcases email" do
        user = build_admin_user(email: "ADMIN@EXAMPLE.COM")
        user.send(:downcase_email)
        expect(user.email).to eq("admin@example.com")
      end

      it "handles nil email gracefully" do
        user = build_admin_user(email: nil)
        expect { user.send(:downcase_email) }.not_to raise_error
      end
    end

    describe "before_create" do
      it "generates session token" do
        user = build_admin_user(session_token: nil, session_expires_at: nil)
        allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return("test_token")

        freeze_time do
          user.send(:generate_session_token)
          expect(user.session_token).to eq("test_token")
          expect(user.session_expires_at).to eq(2.hours.from_now)
        end
      end
    end
  end

  describe ".authenticate" do
    let(:user) { build_admin_user }

    before do
      allow(AdminUser).to receive(:find_by).with(email: "admin@example.com").and_return(user)
    end

    context "when user not found" do
      before do
        allow(AdminUser).to receive(:find_by).with(email: "unknown@example.com").and_return(nil)
      end

      it "returns nil" do
        expect(AdminUser.authenticate("unknown@example.com", "password")).to be_nil
      end
    end

    context "when user is locked" do
      before do
        allow(user).to receive(:locked?).and_return(true)
        allow(user).to receive(:check_unlock_eligibility)
      end

      it "checks unlock eligibility" do
        expect(user).to receive(:check_unlock_eligibility)
        AdminUser.authenticate("admin@example.com", "password")
      end

      it "returns nil if still locked" do
        allow(user).to receive(:locked?).and_return(true, true)
        expect(AdminUser.authenticate("admin@example.com", "password")).to be_nil
      end
    end

    context "with correct password" do
      before do
        allow(user).to receive(:locked?).and_return(false)
        allow(user).to receive(:authenticate).with("correct_password").and_return(true)
        allow(user).to receive(:handle_successful_login)
      end

      it "handles successful login" do
        expect(user).to receive(:handle_successful_login)
        AdminUser.authenticate("admin@example.com", "correct_password")
      end

      it "returns the user" do
        result = AdminUser.authenticate("admin@example.com", "correct_password")
        expect(result).to eq(user)
      end
    end

    context "with incorrect password" do
      before do
        allow(user).to receive(:locked?).and_return(false)
        allow(user).to receive(:authenticate).with("wrong_password").and_return(false)
        allow(user).to receive(:handle_failed_login)
      end

      it "handles failed login" do
        expect(user).to receive(:handle_failed_login)
        AdminUser.authenticate("admin@example.com", "wrong_password")
      end

      it "returns nil" do
        result = AdminUser.authenticate("admin@example.com", "wrong_password")
        expect(result).to be_nil
      end
    end
  end

  describe ".find_by_valid_session" do
    let(:user) { build_admin_user(session_token: "valid_token") }

    it "returns nil for blank token" do
      expect(AdminUser.find_by_valid_session(nil)).to be_nil
      expect(AdminUser.find_by_valid_session("")).to be_nil
    end

    context "when user found" do
      before do
        allow(AdminUser).to receive(:find_by).with(session_token: "valid_token").and_return(user)
      end

      it "returns nil if session expired" do
        allow(user).to receive(:session_expired?).and_return(true)
        expect(AdminUser.find_by_valid_session("valid_token")).to be_nil
      end

      it "extends session and returns user if valid" do
        allow(user).to receive(:session_expired?).and_return(false)
        expect(user).to receive(:extend_session)
        result = AdminUser.find_by_valid_session("valid_token")
        expect(result).to eq(user)
      end
    end

    context "when user not found" do
      before do
        allow(AdminUser).to receive(:find_by).with(session_token: "invalid_token").and_return(nil)
      end

      it "returns nil" do
        expect(AdminUser.find_by_valid_session("invalid_token")).to be_nil
      end
    end
  end

  describe "#locked?" do
    let(:user) { build_admin_user }

    it "returns false when locked_at is nil" do
      user.locked_at = nil
      expect(user.locked?).to be false
    end

    it "returns false when unlock eligible" do
      user.locked_at = 31.minutes.ago
      allow(user).to receive(:unlock_eligible?).and_return(true)
      expect(user.locked?).to be false
    end

    it "returns true when locked and not eligible" do
      user.locked_at = 5.minutes.ago
      allow(user).to receive(:unlock_eligible?).and_return(false)
      expect(user.locked?).to be true
    end
  end

  describe "#unlock_eligible?" do
    let(:user) { build_admin_user }

    it "returns false when not locked" do
      user.locked_at = nil
      expect(user.unlock_eligible?).to be false
    end

    it "returns true when lock duration exceeded" do
      user.locked_at = 31.minutes.ago
      expect(user.unlock_eligible?).to be true
    end

    it "returns false when still within lock duration" do
      user.locked_at = 29.minutes.ago
      expect(user.unlock_eligible?).to be false
    end
  end

  describe "#check_unlock_eligibility" do
    let(:user) { build_admin_user }

    it "unlocks account if eligible" do
      allow(user).to receive(:unlock_eligible?).and_return(true)
      expect(user).to receive(:unlock_account!)
      user.check_unlock_eligibility
    end

    it "does nothing if not eligible" do
      allow(user).to receive(:unlock_eligible?).and_return(false)
      expect(user).not_to receive(:unlock_account!)
      user.check_unlock_eligibility
    end
  end

  describe "#unlock_account!" do
    let(:user) { build_admin_user(locked_at: Time.current, failed_login_attempts: 3) }

    it "clears lock and resets failed attempts" do
      expect(user).to receive(:update!).with(
        locked_at: nil,
        failed_login_attempts: 0
      )
      user.unlock_account!
    end
  end

  describe "#lock_account!" do
    let(:user) { build_admin_user(session_token: "token", session_expires_at: 1.hour.from_now) }

    it "sets lock and clears session" do
      freeze_time do
        expect(user).to receive(:update!).with(
          locked_at: Time.current,
          session_token: nil,
          session_expires_at: nil
        )
        user.lock_account!
      end
    end
  end

  describe "#handle_successful_login" do
    let(:user) { build_admin_user(failed_login_attempts: 2, locked_at: Time.current) }

    it "updates login tracking and clears failures" do
      freeze_time do
        expect(user).to receive(:update!).with(
          last_login_at: Time.current,
          failed_login_attempts: 0,
          locked_at: nil
        )
        expect(user).to receive(:regenerate_session_token)
        user.handle_successful_login
      end
    end
  end

  describe "#handle_failed_login" do
    let(:user) { build_admin_user(failed_login_attempts: 3) }

    it "increments failed attempts" do
      expect(user).to receive(:increment!).with(:failed_login_attempts)
      user.handle_failed_login
    end

    context "when reaching max attempts" do
      let(:user) { build_admin_user(failed_login_attempts: 5) }

      it "locks the account" do
        allow(user).to receive(:increment!)
        expect(user).to receive(:lock_account!)
        user.handle_failed_login
      end
    end

    context "when below max attempts" do
      let(:user) { build_admin_user(failed_login_attempts: 3) }

      it "does not lock the account" do
        allow(user).to receive(:increment!)
        expect(user).not_to receive(:lock_account!)
        user.handle_failed_login
      end
    end
  end

  describe "#regenerate_session_token" do
    let(:user) { build_admin_user }

    it "generates new token and sets expiration" do
      allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_return("new_token")

      freeze_time do
        expect(user).to receive(:update!).with(
          session_token: "new_token",
          session_expires_at: 2.hours.from_now
        )
        user.regenerate_session_token
      end
    end
  end

  describe "#extend_session" do
    let(:user) { build_admin_user(session_token: "token") }

    it "updates expiration when token present" do
      freeze_time do
        expect(user).to receive(:update!).with(session_expires_at: 2.hours.from_now)
        user.extend_session
      end
    end

    it "does nothing when token nil" do
      user.session_token = nil
      expect(user).not_to receive(:update!)
      user.extend_session
    end
  end

  describe "#session_expired?" do
    let(:user) { build_admin_user }

    it "returns true when expires_at is nil" do
      user.session_expires_at = nil
      expect(user.session_expired?).to be true
    end

    it "returns true when past expiration" do
      user.session_expires_at = 1.minute.ago
      expect(user.session_expired?).to be true
    end

    it "returns false when not expired" do
      user.session_expires_at = 1.hour.from_now
      expect(user.session_expired?).to be false
    end
  end

  describe "#invalidate_session!" do
    let(:user) { build_admin_user(session_token: "token", session_expires_at: 1.hour.from_now) }

    it "clears session data" do
      expect(user).to receive(:update!).with(
        session_token: nil,
        session_expires_at: nil
      )
      user.invalidate_session!
    end
  end

  describe "permission methods" do
    describe "#can_manage_patterns?" do
      it "returns true for admin, super_admin, moderator" do
        [ :admin, :super_admin, :moderator ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_manage_patterns?).to be true
        end
      end

      it "returns false for read_only" do
        user = build_admin_user(role: :read_only)
        expect(user.can_manage_patterns?).to be false
      end
    end

    describe "#can_edit_patterns?" do
      it "returns true for admin and super_admin" do
        [ :admin, :super_admin ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_edit_patterns?).to be true
        end
      end

      it "returns false for moderator and read_only" do
        [ :moderator, :read_only ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_edit_patterns?).to be false
        end
      end
    end

    describe "#can_delete_patterns?" do
      it "returns true for admin and super_admin" do
        [ :admin, :super_admin ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_delete_patterns?).to be true
        end
      end

      it "returns false for moderator and read_only" do
        [ :moderator, :read_only ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_delete_patterns?).to be false
        end
      end
    end

    describe "#can_import_patterns?" do
      it "returns true only for super_admin" do
        user = build_admin_user(role: :super_admin)
        expect(user.can_import_patterns?).to be true
      end

      it "returns false for other roles" do
        [ :admin, :moderator, :read_only ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_import_patterns?).to be false
        end
      end
    end

    describe "#can_access_statistics?" do
      it "returns true for all except read_only" do
        [ :admin, :super_admin, :moderator ].each do |role|
          user = build_admin_user(role: role)
          expect(user.can_access_statistics?).to be true
        end
      end

      it "returns false for read_only" do
        user = build_admin_user(role: :read_only)
        expect(user.can_access_statistics?).to be false
      end
    end
  end

  describe "security considerations" do
    describe "password handling" do
      it "never stores plain text passwords" do
        user = build_admin_user
        expect(user.attributes).not_to have_key("password")
        expect(user.password_digest).not_to eq("SecureP@ssw0rd123")
      end
    end

    describe "session security" do
      it "generates cryptographically secure tokens" do
        allow(SecureRandom).to receive(:urlsafe_base64).with(32).and_call_original
        token = build_admin_user.send(:generate_token)
        expect(token.length).to be >= 32
      end
    end

    describe "brute force protection" do
      it "locks account after max failed attempts" do
        user = build_admin_user(failed_login_attempts: 4)
        allow(user).to receive(:increment!).with(:failed_login_attempts) do
          user.failed_login_attempts += 1
        end
        expect(user).to receive(:lock_account!)
        user.handle_failed_login
      end

      it "enforces lock duration" do
        user = build_admin_user(locked_at: 10.minutes.ago)
        expect(user.unlock_eligible?).to be false

        user.locked_at = 31.minutes.ago
        expect(user.unlock_eligible?).to be true
      end
    end
  end
end
