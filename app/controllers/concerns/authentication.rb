# frozen_string_literal: true

# Authentication concern for controllers requiring user authentication
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    helper_method :current_user, :user_signed_in?
  end

  private

  def authenticate_user!
    unless user_signed_in?
      store_location
      redirect_to admin_login_path, alert: "Please sign in to continue."
    end
  end

  def current_user
    @current_user ||= begin
      if session[:admin_session_token].present?
        AdminUser.find_by_valid_session(session[:admin_session_token])
      end
    end
  end

  def user_signed_in?
    current_user.present?
  end

  def current_user_id
    current_user&.id || raise("No authenticated user")
  end

  def store_location
    session[:return_to] = request.fullpath if request.get?
  end

  # Helper method to check if user has specific role
  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "You don't have permission to access this page."
    end
  end

  # Helper method to check if user has specific permission
  def can?(action, resource = nil)
    current_user&.can?(action, resource)
  end

  # Log user actions for audit trail
  def log_user_action(action, details = {})
    Rails.logger.info(
      {
        event: "user_action",
        user_id: current_user&.id,
        action: action,
        details: details,
        controller: controller_name,
        action_name: action_name,
        ip_address: request.remote_ip,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end
end
