require "rails_helper"

# PER-221: Expense delete from show page must redirect to /expenses, not /sync_conflicts
# Root cause: button_to on show.html.erb submitted via Turbo (format.turbo_stream matched),
# which returned a stream response that left the user on the show page of a deleted expense.
# Fix: form uses data-turbo="false" so the HTML redirect response is used instead.
RSpec.describe "Expense DELETE from show page redirect", type: :request do
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

  describe "DELETE /expenses/:id with HTML Accept header (show page form)", :unit do
    it "redirects to /expenses (not /sync_conflicts)" do
      delete expense_path(expense), headers: { "Accept" => "text/html,*/*;q=0.5" }

      expect(response).to redirect_to(expenses_url)
      expect(response.location).not_to include("sync_conflicts")
    end

    it "redirects to /expenses not back to the show page" do
      delete expense_path(expense), headers: { "Accept" => "text/html,*/*;q=0.5" }

      expect(response.location).not_to include(expense_path(expense))
      expect(response.location).to include("/expenses")
    end

    it "soft-deletes the expense" do
      delete expense_path(expense), headers: { "Accept" => "text/html,*/*;q=0.5" }

      expect(Expense.find_by(id: expense.id)).to be_nil
    end

    it "sets a flash notice for the undo notification" do
      delete expense_path(expense), headers: { "Accept" => "text/html,*/*;q=0.5" }

      follow_redirect!
      expect(flash[:notice]).to be_present
    end

    it "sets undo_id in flash for undo functionality" do
      delete expense_path(expense), headers: { "Accept" => "text/html,*/*;q=0.5" }

      expect(flash[:undo_id]).to be_present
    end
  end

  describe "DELETE /expenses/:id with Turbo Stream Accept header (index page inline actions)", :unit do
    it "returns a turbo stream response that removes the row" do
      delete expense_path(expense),
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include("expense_row_#{expense.id}")
      expect(response.body).to include("remove")
    end

    it "does NOT redirect to /sync_conflicts" do
      delete expense_path(expense),
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }

      # Turbo stream response — no redirect, but body must not navigate to sync_conflicts
      expect(response.body).not_to include("sync_conflicts")
    end
  end
end
