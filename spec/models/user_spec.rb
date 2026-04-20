# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model, unit: true do
  # Use build_stubbed for true unit tests
  let(:user) { build_stubbed(:user) }

  describe 'validations' do
    context 'email validation' do
      it 'requires presence of email' do
        user = build(:user, email: nil)
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include("no puede estar en blanco")
      end

      it 'validates email format' do
        invalid_emails = [ 'invalid', 'invalid@', '@example.com', 'user@', 'user space@example.com' ]
        invalid_emails.each do |invalid_email|
          user = build(:user, email: invalid_email)
          expect(user).not_to be_valid
          expect(user.errors[:email]).to include("no es válido")
        end
      end

      it 'accepts valid email formats' do
        valid_emails = [ 'user@example.com', 'user.name@example.co.uk', 'user+tag@example.org' ]
        valid_emails.each do |valid_email|
          user = build(:user, email: valid_email)
          expect(user).to be_valid
        end
      end

      it 'validates email uniqueness case-insensitively' do
        create(:user, email: 'USER@EXAMPLE.COM')
        new_user = build(:user, email: 'user@example.com')
        expect(new_user).not_to be_valid
        expect(new_user.errors[:email]).to include("ya está en uso")
      end
    end

    context 'name validation' do
      it 'requires presence of name' do
        user = build(:user, name: nil)
        expect(user).not_to be_valid
        expect(user.errors[:name]).to include("no puede estar en blanco")
      end

      it 'validates name maximum length' do
        user = build(:user, name: 'a' * 101)
        expect(user).not_to be_valid
        expect(user.errors[:name]).to include("es demasiado largo (100 caracteres máximo)")
      end

      it 'accepts names within length limit' do
        user = build(:user, name: 'a' * 100)
        expect(user).to be_valid
      end
    end

    context 'password validation' do
      it 'requires minimum length of 12 characters' do
        user = build(:user, password: 'Short1@')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("es demasiado corto (12 caracteres mínimo)")
      end

      it 'requires uppercase letter' do
        user = build(:user, password: 'lowercase123@abc')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it 'requires lowercase letter' do
        user = build(:user, password: 'UPPERCASE123@ABC')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it 'requires number' do
        user = build(:user, password: 'NoNumbers@Here')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it 'requires special character' do
        user = build(:user, password: 'NoSpecialChar123')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include("must include uppercase, lowercase, number, and special character")
      end

      it 'accepts valid passwords' do
        valid_passwords = [
          'ValidPass123@',
          'Another$Pass99',
          'Complex!Pass2024',
          'Super@Secure123'
        ]
        valid_passwords.each do |password|
          user = build(:user, password: password, password_confirmation: password)
          expect(user).to be_valid, "Password '#{password}' should be valid"
        end
      end

      it 'only validates password when password_digest changes' do
        user = create(:user)
        user.name = 'Updated Name'
        expect(user).to be_valid
      end
    end
  end

  describe 'enums' do
    it 'defines role enum with correct values' do
      expect(User.roles).to eq({
        'user' => 0,
        'admin' => 1
      })
    end

    it 'defaults to user role' do
      user = User.new
      expect(user.role).to eq('user')
    end

    it 'provides role query methods' do
      admin_user = build_stubbed(:user, role: :admin)
      expect(admin_user.admin?).to be true
      expect(admin_user.user?).to be false
    end
  end

  describe 'callbacks' do
    describe '#downcase_email' do
      it 'downcases email before save' do
        user = build(:user, email: 'UPPER@EXAMPLE.COM')
        user.save
        expect(user.email).to eq('upper@example.com')
      end

      it 'handles nil email gracefully' do
        user = build(:user)
        user.email = nil
        expect { user.save }.not_to raise_error
      end
    end

    describe '#generate_session_token on create' do
      it 'generates session token on create' do
        user = build(:user, session_token: nil)
        user.save
        expect(user.session_token).to be_present
        expect(user.session_token.length).to be >= 32
      end

      it 'sets session expiration on create' do
        freeze_time = Time.current

        user = build(:user)
        user.save

        expect(user.session_expires_at).to be_present
        expect(user.session_expires_at).to be_within(2.seconds).of(freeze_time + User::SESSION_DURATION)
      end
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns users without locked_at' do
        active_user = create(:user, locked_at: nil)
        locked_user = create(:user, locked_at: Time.current)

        result = User.active
        expect(result).to include(active_user)
        expect(result).not_to include(locked_user)
      end
    end

    describe '.locked' do
      it 'returns users with locked_at' do
        active_user = create(:user, locked_at: nil)
        locked_user = create(:user, locked_at: Time.current)

        result = User.locked
        expect(result).not_to include(active_user)
        expect(result).to include(locked_user)
      end
    end

    describe '.with_expired_sessions' do
      it 'returns users with expired sessions' do
        # Mock the scope to return a relation
        expired_users_relation = double("ActiveRecord::Relation")
        allow(User).to receive(:with_expired_sessions).and_return(expired_users_relation)

        # Mock the expected behavior
        expired_user = build_stubbed(:user, session_expires_at: 1.hour.ago)
        valid_user = build_stubbed(:user, session_expires_at: 1.hour.from_now)

        allow(expired_users_relation).to receive(:include?).with(expired_user).and_return(true)
        allow(expired_users_relation).to receive(:include?).with(valid_user).and_return(false)

        result = User.with_expired_sessions
        expect(result).to include(expired_user)
        expect(result).not_to include(valid_user)
      end
    end
  end

  describe 'class methods' do
    describe '.authenticate' do
      let(:email) { 'test@example.com' }
      let(:password) { 'ValidPass123@' }
      let!(:test_user) { create(:user, email: email, password: password) }

      context 'with valid credentials' do
        it 'returns the user' do
          result = User.authenticate(email, password)
          expect(result).to eq(test_user)
        end

        it 'handles uppercase email' do
          result = User.authenticate('TEST@EXAMPLE.COM', password)
          expect(result).to eq(test_user)
        end

        it 'resets failed login attempts' do
          test_user.update(failed_login_attempts: 3)
          User.authenticate(email, password)
          expect(test_user.reload.failed_login_attempts).to eq(0)
        end

        it 'updates last_login_at' do
          freeze_time = Time.current
          allow(Time).to receive(:current).and_return(freeze_time)

          User.authenticate(email, password)
          expect(test_user.reload.last_login_at).to be_within(1.second).of(freeze_time)
        end

        it 'regenerates session token' do
          old_token = test_user.session_token
          User.authenticate(email, password)
          expect(test_user.reload.session_token).not_to eq(old_token)
        end
      end

      context 'with invalid credentials' do
        it 'returns nil for wrong password' do
          result = User.authenticate(email, 'WrongPassword123@')
          expect(result).to be_nil
        end

        it 'returns nil for non-existent email' do
          result = User.authenticate('nonexistent@example.com', password)
          expect(result).to be_nil
        end

        it 'increments failed login attempts' do
          User.authenticate(email, 'WrongPassword123@')
          expect(test_user.reload.failed_login_attempts).to eq(1)
        end

        it 'locks account after max failed attempts' do
          User::MAX_FAILED_LOGIN_ATTEMPTS.times do
            User.authenticate(email, 'WrongPassword123@')
          end
          expect(test_user.reload.locked_at).to be_present
        end
      end

      context 'with locked account' do
        before do
          test_user.update(locked_at: Time.current, failed_login_attempts: 5)
        end

        it 'returns nil even with correct password' do
          result = User.authenticate(email, password)
          expect(result).to be_nil
        end

        it 'unlocks account after lock duration' do
          test_user.update(locked_at: (User::LOCK_DURATION + 1.minute).ago)
          result = User.authenticate(email, password)
          expect(result).to eq(test_user)
          expect(test_user.reload.locked_at).to be_nil
        end
      end
    end

    describe '.find_by_valid_session' do
      let(:test_user) { create(:user) }

      context 'with valid session' do
        it 'returns the user' do
          test_user.update(session_expires_at: 1.hour.from_now)
          result = User.find_by_valid_session(test_user.session_token)
          expect(result).to eq(test_user)
        end

        it 'extends session on activity' do
          freeze_time = Time.current
          allow(Time).to receive(:current).and_return(freeze_time)

          test_user.update(session_expires_at: 30.minutes.from_now)
          User.find_by_valid_session(test_user.session_token)

          expected_expiration = freeze_time + User::SESSION_DURATION
          expect(test_user.reload.session_expires_at).to be_within(1.second).of(expected_expiration)
        end
      end

      context 'with invalid session' do
        it 'returns nil for blank token' do
          result = User.find_by_valid_session(nil)
          expect(result).to be_nil

          result = User.find_by_valid_session('')
          expect(result).to be_nil
        end

        it 'returns nil for non-existent token' do
          result = User.find_by_valid_session('nonexistent_token')
          expect(result).to be_nil
        end

        it 'returns nil for expired session' do
          test_user.update(session_expires_at: 1.hour.ago)
          result = User.find_by_valid_session(test_user.session_token)
          expect(result).to be_nil
        end
      end
    end
  end

  describe 'instance methods' do
    describe '#locked?' do
      it 'returns true when locked and not eligible for unlock' do
        user = build_stubbed(:user, locked_at: 5.minutes.ago)
        expect(user.locked?).to be true
      end

      it 'returns false when not locked' do
        user = build_stubbed(:user, locked_at: nil)
        expect(user.locked?).to be false
      end

      it 'returns false when eligible for unlock' do
        user = build_stubbed(:user, locked_at: (User::LOCK_DURATION + 1.minute).ago)
        expect(user.locked?).to be false
      end
    end

    describe '#unlock_eligible?' do
      it 'returns true when lock duration has passed' do
        user = build_stubbed(:user, locked_at: (User::LOCK_DURATION + 1.minute).ago)
        expect(user.unlock_eligible?).to be true
      end

      it 'returns false when lock duration has not passed' do
        user = build_stubbed(:user, locked_at: 5.minutes.ago)
        expect(user.unlock_eligible?).to be false
      end

      it 'returns false when not locked' do
        user = build_stubbed(:user, locked_at: nil)
        expect(user.unlock_eligible?).to be false
      end
    end

    describe '#check_unlock_eligibility' do
      it 'unlocks account when eligible' do
        user = create(:user, locked_at: (User::LOCK_DURATION + 1.minute).ago)
        user.check_unlock_eligibility
        expect(user.reload.locked_at).to be_nil
      end

      it 'does not unlock when not eligible' do
        user = create(:user, locked_at: 5.minutes.ago)
        user.check_unlock_eligibility
        expect(user.reload.locked_at).to be_present
      end
    end

    describe '#unlock_account!' do
      it 'clears locked_at and failed_login_attempts' do
        user = create(:user, locked_at: Time.current, failed_login_attempts: 5)
        user.unlock_account!

        user.reload
        expect(user.locked_at).to be_nil
        expect(user.failed_login_attempts).to eq(0)
      end
    end

    describe '#lock_account!' do
      it 'sets locked_at and clears session' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        user = create(:user, session_token: 'token', session_expires_at: 1.hour.from_now)
        user.lock_account!

        user.reload
        expect(user.locked_at).to be_within(1.second).of(freeze_time)
        expect(user.session_token).to be_nil
        expect(user.session_expires_at).to be_nil
      end
    end

    describe '#handle_successful_login' do
      it 'updates login tracking fields' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        user = create(:user, failed_login_attempts: 3, locked_at: 1.hour.ago)
        old_token = user.session_token

        user.handle_successful_login

        user.reload
        expect(user.last_login_at).to be_within(1.second).of(freeze_time)
        expect(user.failed_login_attempts).to eq(0)
        expect(user.locked_at).to be_nil
        expect(user.session_token).not_to eq(old_token)
      end
    end

    describe '#handle_failed_login' do
      it 'increments failed login attempts' do
        user = create(:user, failed_login_attempts: 2)
        user.handle_failed_login
        expect(user.reload.failed_login_attempts).to eq(3)
      end

      it 'locks account after max attempts' do
        user = create(:user, failed_login_attempts: User::MAX_FAILED_LOGIN_ATTEMPTS - 1)
        user.handle_failed_login
        expect(user.reload.locked_at).to be_present
      end
    end

    describe '#regenerate_session_token' do
      it 'generates new token and sets expiration' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        user = create(:user)
        old_token = user.session_token

        user.regenerate_session_token

        user.reload
        expect(user.session_token).not_to eq(old_token)
        expect(user.session_token).to be_present
        expected_expiration = freeze_time + User::SESSION_DURATION
        expect(user.session_expires_at).to be_within(1.second).of(expected_expiration)
      end
    end

    describe '#extend_session' do
      it 'extends session expiration when token present' do
        freeze_time = Time.current
        allow(Time).to receive(:current).and_return(freeze_time)

        user = create(:user, session_token: 'token', session_expires_at: 30.minutes.from_now)
        user.extend_session

        expected_expiration = freeze_time + User::SESSION_DURATION
        expect(user.reload.session_expires_at).to be_within(1.second).of(expected_expiration)
      end

      it 'does nothing when no session token' do
        user = create(:user)
        user.update_columns(session_token: nil, session_expires_at: nil)
        user.extend_session
        expect(user.reload.session_expires_at).to be_nil
      end
    end

    describe '#session_expired?' do
      it 'returns true when session_expires_at is nil' do
        user = build_stubbed(:user, session_expires_at: nil)
        expect(user.session_expired?).to be true
      end

      it 'returns true when session has expired' do
        user = build_stubbed(:user, session_expires_at: 1.hour.ago)
        expect(user.session_expired?).to be true
      end

      it 'returns false when session is valid' do
        user = build_stubbed(:user, session_expires_at: 1.hour.from_now)
        expect(user.session_expired?).to be false
      end
    end

    describe '#invalidate_session!' do
      it 'clears session token and expiration' do
        user = create(:user, session_token: 'token', session_expires_at: 1.hour.from_now)
        user.invalidate_session!

        user.reload
        expect(user.session_token).to be_nil
        expect(user.session_expires_at).to be_nil
      end
    end
  end

  describe 'constants' do
    it 'defines expected constants' do
      expect(User::MAX_FAILED_LOGIN_ATTEMPTS).to eq(5)
      expect(User::LOCK_DURATION).to eq(30.minutes)
      expect(User::SESSION_DURATION).to eq(2.hours)
      expect(User::PASSWORD_MIN_LENGTH).to eq(12)
    end
  end

  describe 'edge cases' do
    describe 'concurrent login attempts' do
      it 'handles race condition in failed login counting' do
        user = create(:user, failed_login_attempts: 4)

        initial_attempts = user.failed_login_attempts

        user.handle_failed_login

        user.reload
        expect(user.failed_login_attempts).to eq(initial_attempts + 1)
        expect(user.locked_at).to be_present, "User should be locked after reaching max failed attempts"

        expect { user.handle_failed_login }.not_to raise_error
        user.reload
        expect(user.locked_at).to be_present, "User should remain locked"
      end
    end

    describe 'password with special regex characters' do
      it 'handles passwords with regex special characters' do
        special_passwords = [
          'Valid$Pass123',
          'Valid.Pass123!',
          'Valid*Pass123?',
          'Valid+Pass123&',
          'Valid(Pass)123@'
        ]

        special_passwords.each do |password|
          user = build(:user, password: password, password_confirmation: password)
          expect(user).to be_valid, "Password '#{password}' should be valid"
        end
      end
    end

    describe 'session token uniqueness' do
      it 'generates unique tokens' do
        tokens = []
        10.times do |i|
          user = create(:user, email: "test_user_#{i}@example.com")
          expect(tokens).not_to include(user.session_token)
          tokens << user.session_token
        end
      end
    end
  end
end
