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
        allow(controller).to receive(:authenticate_user!).and_return(true)
        allow(controller).to receive(:current_user).and_return(nil) unless controller.respond_to?(:current_user)
      end
    end
  end

  def mock_user_authentication(user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:user_signed_in?).and_return(true)
  end

  def authenticate_admin_in_controller(admin_user)
    admin_user.regenerate_session_token unless admin_user.session_token.present?
    session[:admin_session_token] = admin_user.reload.session_token
    session[:admin_user_id] = admin_user.id
  end
end

# Test helper for request specs (type: :request)
module RequestAuthenticationHelper
  def sign_in_admin(admin_user)
    post admin_login_path, params: {
      admin_user: {
        email: admin_user.email,
        password: "AdminPassword123!"
      }
    }
  end
end

# Test helper for system specs (type: :system)
module SystemAuthenticationHelper
  def sign_in_admin_user(admin_user, password: "AdminPassword123!")
    visit admin_login_path
    fill_in "admin_user[email]", with: admin_user.email
    fill_in "admin_user[password]", with: password
    click_button "Sign In"
  end
end

RSpec.configure do |config|
  config.include AuthenticationTestHelper, type: :controller
  config.include RequestAuthenticationHelper, type: :request
  config.include SystemAuthenticationHelper, type: :system
end
