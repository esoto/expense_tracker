# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, "'unsafe-inline'" # Tailwind CSS requires inline styles
    policy.connect_src :self, "ws://localhost:*", "wss://localhost:*" # ActionCable WebSocket
  end

  # Generate per-request nonces for permitted importmap and inline scripts.
  # Uses SecureRandom for unique nonces rather than session ID to avoid
  # empty nonces when sessions are not initialized.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Start in report-only mode to identify violations before enforcing.
  config.content_security_policy_report_only = true
end
