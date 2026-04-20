# frozen_string_literal: true

# Controller for end-user authentication (login/logout).
# Parallel to Admin::SessionsController during the unified-user migration;
# PR 12 will merge the two auth paths.
class SessionsController < ApplicationController
  include UserAuthentication

  skip_before_action :authenticate_user!
  skip_before_action :require_authentication, only: [ :new, :create ]

  def new
    # Redirect away if already signed in
    redirect_to root_path, notice: "You are already signed in." if app_user_signed_in?
  end

  def create
    user = User.authenticate(session_params[:email], session_params[:password])

    if user
      handle_successful_login(user)
    else
      handle_failed_login
    end
  end

  def destroy
    log_app_user_action("logout", { email: current_app_user&.email }) if app_user_signed_in?
    clear_user_session
    redirect_to login_path, notice: "You have been signed out successfully."
  end

  private

  def session_params
    params.permit(:email, :password)
  end

  def handle_successful_login(user)
    # Capture return_to before reset_session clears it (PER-180)
    return_to = session[:return_to]
    set_user_session(user)
    session[:return_to] = return_to if return_to.present?
    log_app_user_action("login_success", { email: user.email })

    redirect_to session.delete(:return_to).presence || root_path,
      notice: "Signed in successfully."
  end

  def handle_failed_login
    log_app_user_action("login_failure", { email: session_params[:email] })

    flash.now[:alert] = login_error_message
    render :new, status: :unprocessable_content
  end

  def login_error_message
    user = User.find_by(email: session_params[:email].to_s.downcase)

    if user&.locked?
      "Account locked. Try again in 30 minutes."
    else
      "Invalid email or password."
    end
  end
end
