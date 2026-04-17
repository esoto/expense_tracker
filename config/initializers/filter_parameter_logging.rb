# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# PER-504: two-layer filtering.
#
# filter_parameters — masks request params in logs (controller-level). Rails
# uses partial match via String#include? on stringified names, so `:token`
# already catches `access_token`, `refresh_token`, `api_token`, etc. We still
# list the explicit forms for defense-in-depth and self-documentation of the
# threat model.
#
# `:email` is intentionally OMITTED here: BAC email-sync debugging needs
# operator visibility on account addresses. Note that email masking is NOT
# currently handled by a per-flow logger for sync — StructuredLogger in the
# categorization domain has its own `SENSITIVE_FIELDS` list that doesn't cover
# :email. Exposing account email addresses in sync logs is an accepted
# operational trade-off for BAC debugging.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :ssn, :cvv, :cvc,
  :authorization, :api_key, :access_token, :refresh_token, :admin_key
]

# filter_attributes — masks values in ActiveRecord Model#inspect output and
# in exception-tracker payloads. Production additionally caps inspection via
# `attributes_for_inspect = [:id]` (whitelist), but:
#   - dev/test logs would leak encrypted column values on inspect
#   - Rails console attaches in production for incident response
#   - error-reporter payloads (Sentry/Honeybadger-style) serialize AR objects
#     in all envs
#   - filter_attributes also merges into filter_parameters at boot, so it
#     contributes to request-param logging protection in every env
#
# Note: filter_attributes lives on ActiveRecord::Base, not app.config.
# `:raw_email_content` is listed to protect the encrypted email bodies on
# email_parsing_failures (PER-496) — Rails `encrypts` decrypts transparently
# on attribute read, so an unfiltered `Model#inspect` would leak decrypted
# bank PII.
ActiveRecord::Base.filter_attributes += [
  :passw, :encrypted_password, :encrypted_settings, :token, :secret,
  :raw_email_content
]
