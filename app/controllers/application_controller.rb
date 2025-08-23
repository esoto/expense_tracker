class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern unless Rails.env.test?

  # Handle CSRF for JSON requests
  protect_from_forgery with: :null_session, if: -> { request.format.json? }
end
