# frozen_string_literal: true

require "rails_helper"

# PR 10/10 — User#can_manage_categories? feature flag.
RSpec.describe User, type: :model, integration: true do
  describe "#can_manage_categories?" do
    let(:admin) { create(:user, :admin, email: "flag_admin@example.com") }
    let(:user)  { create(:user, email: "flag_user@example.com") }

    before do
      ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
    end

    it "is always true for admins regardless of the env flag" do
      expect(admin.can_manage_categories?).to be true
    end

    it "is false for regular users when the env flag is unset" do
      expect(user.can_manage_categories?).to be false
    end

    it "is false for regular users when the env flag is the string 'false'" do
      ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "false"
      expect(user.can_manage_categories?).to be false
    ensure
      ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
    end

    it "is true for regular users when the env flag is the string 'true'" do
      ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "true"
      expect(user.can_manage_categories?).to be true
    ensure
      ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
    end
  end
end
