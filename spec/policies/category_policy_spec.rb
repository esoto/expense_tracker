# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryPolicy, type: :policy, integration: true do
  # PR 10: most policy examples predate the feature flag and exercise
  # the authz matrix assuming the flag is on. The flag-off gating is
  # covered in its own describe block below. Keep the global default
  # "flag on" so those earlier cases keep testing the matrix, not the
  # rollout.
  before { ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "true" }
  after  { ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL") }

  let(:user)       { create(:user) }
  let(:other)      { create(:user, email: "other@example.com") }
  let(:admin)      { create(:user, :admin, email: "admin@example.com") }

  let(:shared)          { create(:category, name: "Food", user: nil) }
  let(:own_personal)    { create(:category, name: "Home Food", user: user) }
  let(:others_personal) { create(:category, name: "Out Food", user: other) }

  describe "#show?" do
    it "allows a user to see shared categories" do
      expect(described_class.new(user, shared).show?).to be true
    end

    it "allows a user to see their own personal categories" do
      expect(described_class.new(user, own_personal).show?).to be true
    end

    it "hides another user's personal categories" do
      expect(described_class.new(user, others_personal).show?).to be false
    end

    it "admin can see any category, including other users' personal ones" do
      expect(described_class.new(admin, others_personal).show?).to be true
    end

    it "returns false when user is nil" do
      expect(described_class.new(nil, shared).show?).to be false
    end
  end

  describe "#create?" do
    it "allows a regular user to create personal categories" do
      new_personal = Category.new(user: user, name: "New")
      expect(described_class.new(user, new_personal).create?).to be true
    end

    it "forbids a regular user from creating a shared category (user_id nil)" do
      new_shared = Category.new(user: nil, name: "New Shared")
      expect(described_class.new(user, new_shared).create?).to be false
    end

    it "allows an admin to create either shared or personal categories" do
      new_shared = Category.new(user: nil, name: "New Shared")
      expect(described_class.new(admin, new_shared).create?).to be true
    end

    it "forbids a regular user from creating a personal category owned by someone else" do
      impersonated = Category.new(user: other, name: "Sneaky")
      expect(described_class.new(user, impersonated).create?).to be false
    end

    it "returns false when user is nil" do
      new_personal = Category.new(name: "New")
      expect(described_class.new(nil, new_personal).create?).to be false
    end
  end

  describe "#edit? / #update?" do
    it "regular user can edit own personal" do
      expect(described_class.new(user, own_personal).edit?).to be true
      expect(described_class.new(user, own_personal).update?).to be true
    end

    it "regular user cannot edit shared categories" do
      expect(described_class.new(user, shared).edit?).to be false
    end

    it "regular user cannot edit another user's personal category" do
      expect(described_class.new(user, others_personal).edit?).to be false
    end

    it "admin can edit both shared and personal categories" do
      expect(described_class.new(admin, shared).edit?).to be true
      expect(described_class.new(admin, others_personal).edit?).to be true
    end

    it "returns false when user is nil" do
      expect(described_class.new(nil, shared).edit?).to be false
    end
  end

  describe "#destroy?" do
    it "regular user can destroy own personal" do
      expect(described_class.new(user, own_personal).destroy?).to be true
    end

    it "regular user cannot destroy shared categories" do
      expect(described_class.new(user, shared).destroy?).to be false
    end

    it "regular user cannot destroy another user's personal category" do
      expect(described_class.new(user, others_personal).destroy?).to be false
    end

    it "admin can destroy both" do
      expect(described_class.new(admin, shared).destroy?).to be true
      expect(described_class.new(admin, others_personal).destroy?).to be true
    end
  end

  describe "#manage_patterns?" do
    it "mirrors edit permission — only editable categories expose pattern mgmt" do
      expect(described_class.new(user, own_personal).manage_patterns?).to be true
      expect(described_class.new(user, shared).manage_patterns?).to be false
      expect(described_class.new(admin, shared).manage_patterns?).to be true
    end
  end

  describe ".visible_scope" do
    let!(:shared_seed)      { create(:category, name: "Food",        user: nil) }
    let!(:user_personal)    { create(:category, name: "Home Food",   user: user) }
    let!(:other_personal)   { create(:category, name: "Out Food",    user: other) }

    it "returns shared plus user's personal for a regular user" do
      result = described_class.visible_scope(user)
      expect(result).to include(shared_seed, user_personal)
      expect(result).not_to include(other_personal)
    end

    it "returns all categories for an admin" do
      result = described_class.visible_scope(admin)
      expect(result).to include(shared_seed, user_personal, other_personal)
    end

    it "returns an empty relation when user is nil (fail closed)" do
      expect(described_class.visible_scope(nil)).to be_empty
    end
  end

  describe "feature-flag gating (PR 10)" do
    let(:user)  { create(:user, email: "flag_reg@example.com") }
    let(:admin) { create(:user, :admin, email: "flag_admin@example.com") }
    let(:own)   { create(:category, name: "FlagOwn", user: user) }
    let(:shared_c) { create(:category, name: "FlagShared", user: nil) }

    context "when the flag is off and user is not admin" do
      before { ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL") }

      it "blocks create on own personal" do
        new_personal = Category.new(user: user, name: "X")
        expect(described_class.new(user, new_personal).create?).to be false
      end

      it "blocks edit on own personal" do
        expect(described_class.new(user, own).edit?).to be false
      end

      it "blocks destroy on own personal" do
        expect(described_class.new(user, own).destroy?).to be false
      end

      it "keeps show open for existing owned categories (no silent data loss on rollback)" do
        expect(described_class.new(user, own).show?).to be true
      end

      it "keeps show open for shared categories" do
        expect(described_class.new(user, shared_c).show?).to be true
      end
    end

    context "when the flag is on" do
      around do |example|
        ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "true"
        example.run
        ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
      end

      it "allows create on own personal" do
        new_personal = Category.new(user: user, name: "X")
        expect(described_class.new(user, new_personal).create?).to be true
      end

      it "allows edit + destroy on own personal" do
        expect(described_class.new(user, own).edit?).to be true
        expect(described_class.new(user, own).destroy?).to be true
      end
    end

    it "admins bypass the flag" do
      expect(described_class.new(admin, shared_c).edit?).to be true
    end
  end

  describe ".can_access?" do
    let(:user)  { create(:user, email: "access_user@example.com") }
    let(:admin) { create(:user, :admin, email: "access_admin@example.com") }

    before { ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL") }

    it "returns false for nil" do
      expect(described_class.can_access?(nil)).to be false
    end

    it "returns true for admin regardless of flag" do
      expect(described_class.can_access?(admin)).to be true
    end

    it "returns false for regular user without flag" do
      expect(described_class.can_access?(user)).to be false
    end

    it "returns true for regular user when flag is on" do
      ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "true"
      expect(described_class.can_access?(user)).to be true
    ensure
      ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
    end
  end
end
