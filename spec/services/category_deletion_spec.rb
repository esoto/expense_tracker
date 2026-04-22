# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::CategoryDeletion, type: :service, integration: true do
  let!(:user)  { create(:user, email: "cd_user@example.com") }
  let!(:other) { create(:user, email: "cd_other@example.com") }
  let!(:email_account) { create(:email_account, user: user) }

  describe ".call with :orphan" do
    it "destroys an empty personal category" do
      c = create(:category, name: "EmptyPersonal", user: user)
      result = described_class.new(category: c, actor: user, strategy: :orphan).call
      expect(result.success).to be true
      expect(Category.exists?(c.id)).to be false
    end

    it "nullifies expenses' category_id" do
      c = create(:category, name: "HasExpenses", user: user)
      expense = create(:expense, category: c, email_account: email_account)
      result = described_class.new(category: c, actor: user, strategy: :orphan).call
      expect(result.success).to be true
      expect(expense.reload.category_id).to be_nil
    end

    it "cascades patterns + feedbacks via dependent: :destroy" do
      c = create(:category, name: "HasPatterns", user: user)
      create(:categorization_pattern, category: c, pattern_type: "merchant", pattern_value: "xx")
      expect {
        described_class.new(category: c, actor: user, strategy: :orphan).call
      }.to change { CategorizationPattern.count }.by(-1)
    end

    it "nullifies children categories (detached, not deleted)" do
      parent   = create(:category, name: "OrphanParent", user: user)
      child    = create(:category, name: "OrphanChild", user: user, parent: parent)
      described_class.new(category: parent, actor: user, strategy: :orphan).call
      child.reload
      expect(child.parent_id).to be_nil
      expect(Category.exists?(child.id)).to be true
    end

    it "nullifies attached budgets when orphaning" do
      c = create(:category, name: "Budgeted", user: user)
      budget = create(:budget,
                      email_account: email_account,
                      user: user,
                      category: c,
                      name: "Food",
                      amount: 100,
                      period: :monthly,
                      start_date: Date.current,
                      currency: "CRC")
      described_class.new(category: c, actor: user, strategy: :orphan).call
      expect(budget.reload.category_id).to be_nil
    end

    it "refuses :orphan for shared categories (admin must reassign)" do
      shared = create(:category, name: "SharedCantOrphan", user: nil)
      admin = create(:user, :admin, email: "cd_admin_orphan@example.com")
      result = described_class.new(category: shared, actor: admin, strategy: :orphan).call
      expect(result.success).to be false
      expect(result.error).to match(/reassign/i)
    end
  end

  describe ".call with :reassign" do
    let!(:source) { create(:category, name: "SourceReassign", user: user) }
    let!(:target) { create(:category, name: "TargetReassign", user: user) }

    it "moves expenses to the target category" do
      expense = create(:expense, category: source, email_account: email_account)
      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: target).call
      expect(result.success).to be true
      expect(expense.reload.category_id).to eq(target.id)
    end

    it "moves children to the target category" do
      child = create(:category, name: "ChildToMove", user: user, parent: source)
      described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: target).call
      expect(child.reload.parent_id).to eq(target.id)
    end

    it "moves attached budgets to the target category" do
      budget = create(:budget,
                      email_account: email_account,
                      user: user,
                      category: source,
                      name: "Reassigned Budget",
                      amount: 200,
                      period: :monthly,
                      start_date: Date.current,
                      currency: "CRC")
      described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: target).call
      expect(budget.reload.category_id).to eq(target.id)
    end

    it "destroys patterns on the source (they belong to source's identity)" do
      create(:categorization_pattern, category: source, pattern_type: "merchant", pattern_value: "srcpat")
      expect {
        described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: target).call
      }.to change { CategorizationPattern.count }.by(-1)
    end

    it "refuses when reassign_to is missing" do
      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: nil).call
      expect(result.success).to be false
      expect(result.error).to match(/target/i)
    end

    it "refuses when reassign_to == category (self-reassignment)" do
      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: source).call
      expect(result.success).to be false
    end

    it "refuses when reassign_to is not visible to the actor" do
      others_cat = create(:category, name: "OthersCatForReassign", user: other)
      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: others_cat).call
      expect(result.success).to be false
      expect(Category.exists?(source.id)).to be true
    end

    it "refuses when reassign_to is a direct child of the category being deleted (would create a cycle)" do
      child = create(:category, name: "CycleChild", user: user, parent: source)
      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: child).call
      expect(result.success).to be false
      expect(result.error).to match(/descendant/i)
      expect(Category.exists?(source.id)).to be true
      expect(child.reload.parent_id).to eq(source.id) # unchanged
    end

    it "rolls back fully when reassigning would violate a unique budget constraint" do
      # Existing active monthly budget on target for the same email_account
      create(:budget,
             email_account: email_account,
             user: user,
             category: target,
             name: "Existing Target Budget",
             amount: 500,
             period: :monthly,
             start_date: Date.current,
             currency: "CRC")
      source_budget = create(:budget,
                             email_account: email_account,
                             user: user,
                             category: source,
                             name: "Source Budget",
                             amount: 100,
                             period: :monthly,
                             start_date: Date.current,
                             currency: "CRC")
      source_expense = create(:expense, category: source, email_account: email_account)
      source_child   = create(:category, name: "SourceChild", user: user, parent: source)
      source_pattern = create(:categorization_pattern,
                              category: source,
                              pattern_type: "merchant",
                              pattern_value: "rb_src")

      result = described_class.new(category: source, actor: user, strategy: :reassign, reassign_to: target).call
      expect(result.success).to be false

      # Full rollback — nothing moved, nothing deleted
      expect(Category.exists?(source.id)).to be true
      expect(source_expense.reload.category_id).to eq(source.id)
      expect(source_child.reload.parent_id).to eq(source.id)
      expect(source_budget.reload.category_id).to eq(source.id)
      expect(CategorizationPattern.exists?(source_pattern.id)).to be true
    end
  end

  describe "authorization" do
    it "refuses when actor cannot destroy the category" do
      others_cat = create(:category, name: "NotYours", user: other)
      result = described_class.new(category: others_cat, actor: user, strategy: :orphan).call
      expect(result.success).to be false
      expect(result.error).to match(/permission|cannot/i)
      expect(Category.exists?(others_cat.id)).to be true
    end

    it "allows admins to delete any category" do
      admin = create(:user, :admin, email: "cd_admin@example.com")
      target = create(:category, name: "AdminTarget", user: nil)
      # shared requires reassign; build a reassign destination
      reassign_to = create(:category, name: "AdminFallback", user: nil)
      result = described_class.new(category: target,
                                   actor: admin,
                                   strategy: :reassign,
                                   reassign_to: reassign_to).call
      expect(result.success).to be true
      expect(Category.exists?(target.id)).to be false
    end
  end

  describe "shared category with personal children" do
    it "blocks deletion while personal children exist under the shared parent and preserves both" do
      shared_parent = create(:category, name: "SharedParent", user: nil)
      child = create(:category, name: "PersonalChildUnderShared", user: user, parent: shared_parent)
      reassign_to = create(:category, name: "SharedFallback", user: nil)

      admin = create(:user, :admin, email: "cd_admin2@example.com")
      result = described_class.new(category: shared_parent,
                                   actor: admin,
                                   strategy: :reassign,
                                   reassign_to: reassign_to).call
      expect(result.success).to be false
      expect(result.error).to match(/personal children/i)

      # Nothing moved, nothing deleted.
      expect(Category.exists?(shared_parent.id)).to be true
      expect(child.reload.parent_id).to eq(shared_parent.id)
      expect(child.user_id).to eq(user.id)
    end
  end
end
