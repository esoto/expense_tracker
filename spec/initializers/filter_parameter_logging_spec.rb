# frozen_string_literal: true

require "rails_helper"

# PER-504: Initializer-level spec asserting the parameter/attribute filter
# configuration is effective. Rails evaluates initializers once at boot,
# then compiles the filter list into regexes (ActiveSupport::ParameterFilter)
# and merges AR per-model `filter_attributes`. We test BEHAVIOR (does a
# given key get masked?) rather than internal array representation, because
# the latter changes shape after compilation.
RSpec.describe "config/initializers/filter_parameter_logging.rb", unit: true do
  # Use the LIVE ActionDispatch parameter filter — this is what Rails applies
  # to logged request parameters end-to-end.
  let(:param_filter) do
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end

  def filtered(key, value = "shhh")
    param_filter.filter({ key.to_s => value }).fetch(key.to_s)
  end

  describe "filter_parameters (request params)" do
    # The existing partial-match patterns (Rails uses include? on stringified
    # names) already cover a lot — :token matches access_token/refresh_token/
    # api_token; :_key matches api_key/admin_key. We still list the explicit
    # forms for defense-in-depth and self-documentation of the threat model.
    it "masks password-adjacent keys" do
      expect(filtered("password")).to eq("[FILTERED]")
      expect(filtered("user_password")).to eq("[FILTERED]")
      expect(filtered("encrypted_password")).to eq("[FILTERED]")
    end

    it "masks secret / token / api-key variants" do
      expect(filtered("secret")).to eq("[FILTERED]")
      expect(filtered("api_token")).to eq("[FILTERED]")
      expect(filtered("access_token")).to eq("[FILTERED]")
      expect(filtered("refresh_token")).to eq("[FILTERED]")
      expect(filtered("api_key")).to eq("[FILTERED]")
      expect(filtered("admin_key")).to eq("[FILTERED]")
    end

    it "masks the Authorization header key (PER-504: not covered by any preexisting partial pattern)" do
      expect(filtered("authorization")).to eq("[FILTERED]")
      expect(filtered("Authorization")).to eq("[FILTERED]")
    end

    it "masks crypto / identity / card data" do
      expect(filtered("crypt_salt")).to eq("[FILTERED]")
      expect(filtered("salt")).to eq("[FILTERED]")
      expect(filtered("certificate")).to eq("[FILTERED]")
      expect(filtered("otp_code")).to eq("[FILTERED]")
      expect(filtered("ssn")).to eq("[FILTERED]")
      expect(filtered("cvv")).to eq("[FILTERED]")
      expect(filtered("cvc")).to eq("[FILTERED]")
    end

    it "intentionally does NOT mask :email — BAC email sync logging needs operator visibility" do
      # PII masking for email bodies is handled by the per-flow StructuredLogger
      # in the email parser, not globally. PER-504 explicitly loosens this to
      # unblock BAC debugging.
      expect(filtered("email", "user@example.com")).to eq("user@example.com")
      expect(filtered("user_email", "user@example.com")).to eq("user@example.com")
    end
  end

  describe "filter_attributes (ActiveRecord Model#inspect)" do
    # filter_attributes masks attribute values when ActiveRecord models are
    # inspected (dev/test logs, exception backtraces, console output).
    # Production additionally caps exposure via `attributes_for_inspect = [:id]`,
    # but dev/test logs and error-reporter captures still need this.
    let(:filter_attributes) { ActiveRecord::Base.filter_attributes }

    it "is configured (non-empty)" do
      expect(filter_attributes).not_to be_empty
    end

    it "masks encrypted + secret attributes" do
      # filter_attributes is NOT yet compiled at this level — it remains a
      # symbol array until ActiveRecord::AttributeMethods::Serialization
      # builds the per-model inspector. Direct symbol inclusion is safe here.
      expect(filter_attributes).to include(:passw, :encrypted_password, :encrypted_settings, :token, :secret)
    end
  end
end
