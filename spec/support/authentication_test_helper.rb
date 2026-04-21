# frozen_string_literal: true

# Test helper for controller authentication (type: :controller)
module AuthenticationTestHelper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def setup_authentication_mocks
      before do
        # Use instance-level mocking to avoid class-level pollution
        allow(controller).to receive(:require_authentication).and_return(true)
        allow(controller).to receive(:check_session_expiry).and_return(true)
        allow(controller).to receive(:current_user).and_return(nil) unless controller.respond_to?(:current_user)
      end
    end
  end

  # PR-12: Legacy alias — previously came from AdminAuthentication concern.
  # Stubs unified UserAuthentication before_actions so controller specs can run
  # without a real session when passing a User (or double) as the current user.
  def authenticate_admin_in_controller(user)
    mock_user_authentication(user)
    allow(controller).to receive(:require_admin!).and_return(true)
    allow(controller).to receive(:current_admin_user).and_return(user)
    allow(controller).to receive(:admin_signed_in?).and_return(true)
  end

  def mock_user_authentication(user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:current_app_user).and_return(user)
    allow(controller).to receive(:require_authentication).and_return(true)
    allow(controller).to receive(:check_session_expiry).and_return(true)
    allow(controller).to receive(:user_signed_in?).and_return(true)
    allow(controller).to receive(:app_user_signed_in?).and_return(true)
  end
end

# Test helper for request specs (type: :request)
module RequestAuthenticationHelper
  # PR-12: Unified sign-in helper — uses a User (any role).
  # Password defaults to the User factory default ("TestPass123!").
  # Pass an explicit password if the user was created with a different one.
  def sign_in_as(user, password: "TestPass123!")
    post login_path, params: {
      email: user.email,
      password: password
    }
  end

  # Sign in a User (any role). Password defaults to the User factory default.
  # Specs that create users with a custom password MUST pass it explicitly.
  def sign_in_admin(user, password: "TestPass123!")
    sign_in_as(user, password: password)
  end
end

# Test helper for system specs (type: :system)
module SystemAuthenticationHelper
  def sign_in_as_user(user, password: "Password123!")
    visit login_path
    fill_in "email", with: user.email
    fill_in "password", with: password
    click_button "Iniciar Sesión"
  end

  # Legacy alias for backward compatibility
  def sign_in_admin_user(admin_user, password: "AdminPassword123!")
    sign_in_as_user(admin_user, password: password)
  end
end

RSpec.configure do |config|
  config.include AuthenticationTestHelper, type: :controller
  config.include RequestAuthenticationHelper, type: :request
  config.include SystemAuthenticationHelper, type: :system
end
