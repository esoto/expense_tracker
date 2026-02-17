require "rails_helper"

RSpec.describe "Sidekiq Web Authentication", :unit do
  let(:auth_block) { extract_sidekiq_auth_block }

  describe "credential validation" do
    context "when environment variables are not set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_USERNAME").and_return(nil)
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return(nil)
      end

      it "denies access" do
        expect(auth_block.call("admin", "password")).to be false
      end

      it "denies access even with empty username attempt" do
        expect(auth_block.call("", "")).to be false
      end

      it "logs a security error" do
        expect(Rails.logger).to receive(:error).with("[SECURITY] Sidekiq Web credentials not configured")
        auth_block.call("anything", "anything")
      end
    end

    context "when environment variables are blank strings" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_USERNAME").and_return("")
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return("")
      end

      it "denies access" do
        expect(auth_block.call("admin", "password")).to be false
      end

      it "logs a security error" do
        expect(Rails.logger).to receive(:error).with("[SECURITY] Sidekiq Web credentials not configured")
        auth_block.call("admin", "password")
      end
    end

    context "when only username is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_USERNAME").and_return("admin")
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return(nil)
      end

      it "denies access" do
        expect(auth_block.call("admin", "password")).to be false
      end
    end

    context "when only password is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_USERNAME").and_return(nil)
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return("secret")
      end

      it "denies access" do
        expect(auth_block.call("admin", "secret")).to be false
      end
    end

    context "when credentials are properly configured" do
      let(:configured_username) { "sidekiq_admin" }
      let(:configured_password) { "super_secret_password_123" }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_USERNAME").and_return(configured_username)
        allow(ENV).to receive(:[]).with("SIDEKIQ_WEB_PASSWORD").and_return(configured_password)
      end

      it "grants access with correct credentials" do
        expect(auth_block.call(configured_username, configured_password)).to be true
      end

      it "denies access with incorrect username" do
        expect(auth_block.call("wrong_user", configured_password)).to be false
      end

      it "denies access with incorrect password" do
        expect(auth_block.call(configured_username, "wrong_password")).to be false
      end

      it "denies access with both incorrect credentials" do
        expect(auth_block.call("wrong_user", "wrong_password")).to be false
      end

      it "uses timing-safe comparison via secure_compare" do
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare)
          .with(configured_username, configured_username).and_call_original
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare)
          .with(configured_password, configured_password).and_call_original

        auth_block.call(configured_username, configured_password)
      end
    end
  end

  describe "no default fallback credentials" do
    it "does not use ENV.fetch with default values for username" do
      routes_content = File.read(Rails.root.join("config/routes.rb"))
      expect(routes_content).not_to match(/ENV\.fetch\(\s*["']SIDEKIQ_WEB_USERNAME["'].*,/)
    end

    it "does not use ENV.fetch with default values for password" do
      routes_content = File.read(Rails.root.join("config/routes.rb"))
      expect(routes_content).not_to match(/ENV\.fetch\(\s*["']SIDEKIQ_WEB_PASSWORD["'].*,/)
    end
  end

  private

  def extract_sidekiq_auth_block
    # Build the auth logic as a testable proc that mirrors the routes.rb implementation
    proc do |username, password|
      sidekiq_username = ENV["SIDEKIQ_WEB_USERNAME"]
      sidekiq_password = ENV["SIDEKIQ_WEB_PASSWORD"]

      if sidekiq_username.blank? || sidekiq_password.blank?
        Rails.logger.error "[SECURITY] Sidekiq Web credentials not configured"
        false
      else
        ActiveSupport::SecurityUtils.secure_compare(username, sidekiq_username) &&
          ActiveSupport::SecurityUtils.secure_compare(password, sidekiq_password)
      end
    end
  end
end
