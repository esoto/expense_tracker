class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern unless Rails.env.test?

  # Handle CSRF for JSON requests
  protect_from_forgery with: :null_session, if: -> { request.format.json? }

  private

  def set_locale
    I18n.locale = session[:locale]&.to_sym if I18n.available_locales.include?(session[:locale]&.to_sym)
  end
end
