require "rails_helper"

# PER-209: Expense delete must redirect to /expenses, not /sync_conflicts
RSpec.describe "Expense DELETE redirect", type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      status: "pending",
      merchant_name: "Test Merchant",
      amount: 1500
    )
  end

  before { sign_in_admin(admin_user) }

  describe "DELETE /expenses/:id", :unit do
    it "redirects to /expenses (not /sync_conflicts)" do
      delete expense_path(expense)

      expect(response).to redirect_to(expenses_url)
      expect(response.location).not_to include("sync_conflicts")
    end

    it "soft-deletes the expense" do
      delete expense_path(expense)

      expect(Expense.find_by(id: expense.id)).to be_nil
    end

    it "sets a notice flash message" do
      delete expense_path(expense)

      follow_redirect!
      # Notice is present (exact wording handled by i18n)
      expect(flash[:notice]).to be_present
    end

    it "includes undo_id in flash for undo functionality" do
      delete expense_path(expense)

      expect(flash[:undo_id]).to be_present
    end

    context "when expense does not exist" do
      it "redirects to /expenses with an alert" do
        delete expense_path(id: 999_999_999)

        expect(response).to redirect_to(expenses_path)
        expect(response.location).not_to include("sync_conflicts")
      end
    end

    context "when deletion raises a StandardError" do
      before do
        allow_any_instance_of(Expense).to receive(:soft_delete!).and_raise(StandardError, "db error")
      end

      it "still redirects to /expenses, not /sync_conflicts" do
        delete expense_path(expense)

        expect(response).to redirect_to(expenses_url)
        expect(response.location).not_to include("sync_conflicts")
      end
    end
  end
end
