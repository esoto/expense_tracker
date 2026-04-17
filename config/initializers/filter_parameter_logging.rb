# Be sure to restart your server when you modify this file.

# PER-504: two-layer filtering.
#
# filter_parameters — masks request params in logs (controller-level). Rails
# uses partial match via String#include? on stringified names, so `:token`
# already catches `access_token`, `refresh_token`, `api_token`, etc. We still
# list the explicit forms for defense-in-depth and self-documentation of the
# threat model.
#
# `:email` is intentionally OMITTED: BAC email-sync debugging needs operator
# visibility on account addresses. PII masking for logged email bodies is
# handled by the per-flow StructuredLogger in the email parser, not here.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :ssn, :cvv, :cvc,
  :authorization, :api_key, :access_token, :refresh_token, :admin_key
]

# filter_attributes — masks values in ActiveRecord Model#inspect output (dev,
# test, console, and exception-tracker payloads). Production additionally
# caps inspection via `attributes_for_inspect = [:id]`, but dev/test logs
# and error-reporter captures would otherwise leak `encrypted_password`,
# `encrypted_settings`, and various token/secret columns.
#
# Note: filter_attributes lives on ActiveRecord::Base, not app.config.
# Loaded after ActiveRecord initializes (initializers fire after AR boot).
ActiveRecord::Base.filter_attributes += [
  :passw, :encrypted_password, :encrypted_settings, :token, :secret
]
