# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  describe "CSP report-only header", :unit do
    it "includes Content-Security-Policy-Report-Only header" do
      get rails_health_check_path

      expect(response).to have_http_status(:success)
      expect(response.headers["Content-Security-Policy-Report-Only"]).to be_present
    end

    it "includes CSP header on redirect responses" do
      get root_path

      # Unauthenticated users are redirected to login
      expect(response).to have_http_status(:redirect)
      expect(response.headers["Content-Security-Policy-Report-Only"]).to be_present
    end

    it "does not include enforcing Content-Security-Policy header" do
      get rails_health_check_path

      expect(response.headers["Content-Security-Policy"]).to be_nil
    end
  end

  describe "CSP directive values", :unit do
    before { get rails_health_check_path }

    let(:csp_header) { response.headers["Content-Security-Policy-Report-Only"] }

    it "sets default-src to self" do
      expect(csp_header).to include("default-src 'self'")
    end

    it "sets font-src to self and data" do
      expect(csp_header).to include("font-src 'self' data:")
    end

    it "sets img-src to self, data, and https" do
      expect(csp_header).to include("img-src 'self' data: https:")
    end

    it "sets object-src to none" do
      expect(csp_header).to include("object-src 'none'")
    end

    it "sets script-src to self with nonce" do
      expect(csp_header).to match(/script-src 'self' 'nonce-[^']+/)
    end

    it "sets style-src to self with unsafe-inline for Tailwind" do
      expect(csp_header).to include("style-src 'self' 'unsafe-inline'")
    end

    it "sets connect-src to allow WebSocket connections for ActionCable" do
      expect(csp_header).to include("connect-src 'self'")
      expect(csp_header).to match(/ws:\/\/localhost:\*|wss:\/\/localhost:\*/)
    end
  end

  describe "CSP nonce generation", :unit do
    it "includes a nonce in the script-src directive" do
      get rails_health_check_path

      csp_header = response.headers["Content-Security-Policy-Report-Only"]
      expect(csp_header).to match(/script-src[^;]*'nonce-[A-Za-z0-9+\/=]+'/)
    end

    it "generates different nonces for different sessions" do
      get rails_health_check_path
      first_csp = response.headers["Content-Security-Policy-Report-Only"]
      first_nonce = first_csp[/nonce-([A-Za-z0-9+\/=]+)/, 1]

      # Reset session for a fresh request with a new session
      reset!
      get rails_health_check_path
      second_csp = response.headers["Content-Security-Policy-Report-Only"]
      second_nonce = second_csp[/nonce-([A-Za-z0-9+\/=]+)/, 1]

      # Different sessions should produce different nonces
      expect(first_nonce).not_to eq(second_nonce)
    end
  end
end
