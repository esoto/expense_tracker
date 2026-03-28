# frozen_string_literal: true

module Admin
  # Controller for admin authentication (login/logout)
  class SessionsController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :redirect_if_authenticated, only: [ :new, :create ]

    # Rate limiting for login attempts
    before_action :check_login_rate_limit, only: [ :create ]

    layout "admin_login"

    def new
      @admin_user = AdminUser.new
    end

    def create
      @admin_user = AdminUser.authenticate(
        session_params[:email],
        session_params[:password]
      )

      if @admin_user
        handle_successful_login
      else
        handle_failed_login
      end
    end

    def destroy
      if defined?(current_admin_user) && current_admin_user
        current_admin_user.invalidate_session!
        log_admin_action("logout", { email: current_admin_user.email })
      end

      reset_session
      redirect_to admin_login_path, notice: "You have been signed out successfully."
    end

    private

    def session_params
      params.require(:admin_user).permit(:email, :password, :remember_me, :otp_code)
    end

    def redirect_if_authenticated
      if admin_signed_in?
        redirect_to admin_patterns_path, notice: "You are already signed in."
      end
    end

    def handle_successful_login
      # Capture return_to before reset_session clears it (PER-180)
      return_to = session[:return_to]
      set_admin_session(@admin_user)
      session[:return_to] = return_to if return_to.present?
      log_successful_login

      redirect_back_or(admin_patterns_path)
    end

    def handle_failed_login
      log_failed_login

      flash.now[:alert] = login_error_message
      # PER-181: Deliberately exclude :password so it is never re-populated.
      # The view also forces value="" as defense-in-depth.
      @admin_user = AdminUser.new(email: session_params[:email])
      render :new, status: :unprocessable_content
    end

    def login_error_message
      user = AdminUser.find_by(email: session_params[:email]&.downcase)

      if user&.locked?
        "Your account has been locked due to too many failed login attempts. Please try again later or contact support."
      else
        "Invalid email or password."
      end
    end

    def check_login_rate_limit
      # Additional rate limiting check for login attempts
      # This works in conjunction with Rack::Attack
      ip_key = "login_attempts:#{request.remote_ip}"
      attempts = Rails.cache.read(ip_key).to_i

      if attempts >= 10
        render_too_many_requests
        return
      end

      Rails.cache.write(ip_key, attempts + 1, expires_in: 15.minutes)
    end

    def render_too_many_requests
      flash.now[:alert] = "Too many login attempts. Please try again later."
      @admin_user = AdminUser.new

      respond_to do |format|
        format.html { render :new, status: :too_many_requests }
        format.json { render json: { error: "Too many requests" }, status: :too_many_requests }
        format.any  { render :new, status: :too_many_requests }
      end
    end

    def log_successful_login
      Rails.logger.info(
        {
          event: "admin_login_success",
          admin_user_id: @admin_user.id,
          email: @admin_user.email,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          timestamp: Time.current.iso8601
        }.to_json
      )
    end

    def log_failed_login
      Rails.logger.warn(
        {
          event: "admin_login_failed",
          email: session_params[:email],
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          timestamp: Time.current.iso8601
        }.to_json
      )
    end

    def admin_signed_in?
      # PER-213: The sessions controller checks sign-in to redirect away from
      # the login page when already authenticated. Use default extend: true since
      # visiting the login page while already logged in is genuine user activity.
      session[:admin_session_token].present? &&
        AdminUser.find_by_valid_session(session[:admin_session_token]).present?
    end

    def set_admin_session(admin_user)
      reset_session # Prevent session fixation
      session[:admin_session_token] = admin_user.session_token
      session[:admin_user_id] = admin_user.id
      session[:admin_session_expires_at] = admin_user.session_expires_at&.iso8601
    end

    def redirect_back_or(default)
      return_to = valid_return_to_path(session.delete(:return_to))
      redirect_to(return_to || default)
    end

    # Only redirect back to safe admin paths to prevent open redirect and
    # routing errors caused by stale or external session[:return_to] values.
    # This fixes PER-179: stale session[:return_to] could hold "/login"
    # (non-existent route), causing RoutingError after successful login.
    def valid_return_to_path(path)
      return nil if path.blank?
      return nil unless path.start_with?("/admin/") || path == "/admin"

      path
    end

    def log_admin_action(action, details = {})
      Rails.logger.info(
        {
          event: "admin_action",
          action: action,
          details: details,
          ip_address: request.remote_ip,
          timestamp: Time.current.iso8601
        }.to_json
      )
    end
  end
end
