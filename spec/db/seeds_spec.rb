# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds.rb" do
  let(:admin_email) { "seeds-spec-admin@example.com" }
  let(:admin_password) { "SeedsSpecPass123!" }
  let(:non_admin_email) { "seeds-spec-non-admin@example.com" }

  around do |example|
    original_admin_email = ENV["ADMIN_EMAIL"]
    original_admin_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_EMAIL"] = admin_email
    ENV["ADMIN_PASSWORD"] = admin_password
    example.run
  ensure
    ENV["ADMIN_EMAIL"] = original_admin_email
    ENV["ADMIN_PASSWORD"] = original_admin_password
  end

  def load_seeds
    original_stdout = $stdout
    $stdout = StringIO.new
    load Rails.root.join("db/seeds.rb")
  ensure
    $stdout = original_stdout
  end

  describe "ApiToken seeding" do
    it "creates the admin's own token even when another user already owns a token with the same name" do
      non_admin = User.create!(
        email: non_admin_email,
        name: "Non Admin",
        password: "NonAdminPass123!",
        role: :user
      )
      non_admin_token = non_admin.api_tokens.create!(
        name: "iPhone Shortcuts",
        active: true,
        expires_at: 6.months.from_now
      )

      load_seeds

      admin = User.find_by!(email: admin_email)
      expect(admin.role).to eq("admin")

      admin_token = admin.api_tokens.find_by(name: "iPhone Shortcuts")
      expect(admin_token).to be_present
      expect(admin_token.id).not_to eq(non_admin_token.id)

      # The non-admin's token must remain untouched and still owned by them.
      expect(non_admin.api_tokens.reload.find_by(name: "iPhone Shortcuts")).to eq(non_admin_token)
    end
  end
end
