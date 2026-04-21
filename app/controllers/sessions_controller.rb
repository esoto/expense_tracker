# frozen_string_literal: true

# Controller for end-user AND admin authentication (login/logout).
# As of PR 12 this is the only login controller — Admin::SessionsController
# was deleted and /admin/login removed. Role-based authorization happens in
# Admin::BaseController via `before_action :require_admin!`.
class SessionsController < ApplicationController
  include UserAuthentication

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

    # redirect_back_or runs the stored path through valid_return_to_path,
    # which rejects /admin and off-origin paths before redirecting.
    flash[:notice] = "Signed in successfully."
    redirect_back_or(root_path)
  end

  def handle_failed_login
    log_app_user_action("login_failure", { email: session_params[:email] })

    # Always use a generic message to avoid leaking whether the email exists
    # or whether an account is locked (user-enumeration vector). A locked user
    # who forgets their password waits out the 30-minute LOCK_DURATION.
    flash.now[:alert] = "Invalid email or password."
    render :new, status: :unprocessable_content
  end
end
