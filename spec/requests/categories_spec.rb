# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories API", type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }

  describe "GET /categories.json", :unit do
    context "when authenticated" do
      before { sign_in_admin(admin_user) }

      it "returns 200 with categories as JSON" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end

      it "returns all categories with expected attributes" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.length).to be >= 2

        first = json.find { |c| c["name"] == "Food" }
        expect(first).to include(
          "id" => category_food.id,
          "name" => "Food",
          "color" => "#FF6B6B"
        )
        expect(first).to have_key("parent_id")
      end

      it "returns categories ordered by name" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        json = JSON.parse(response.body)
        names = json.map { |c| c["name"] }
        expect(names).to eq(names.sort)
      end
    end

    context "when unauthenticated" do
      it "returns 401 for JSON requests instead of redirecting" do
        get categories_path(format: :json),
            headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Authentication required")
      end

      it "returns 401 for XHR requests" do
        get categories_path(format: :json),
            headers: {
              "Accept" => "application/json",
              "X-Requested-With" => "XMLHttpRequest"
            }

        expect(response).to have_http_status(:unauthorized)
      end

      it "redirects to admin login for HTML requests" do
        get categories_path

        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "GET /categories (HTML)", :integration do
    let!(:user)  { create(:user, email: "crud_user@example.com") }
    let!(:other) { create(:user, email: "crud_other@example.com") }
    let!(:shared_one)     { create(:category, name: "Shared1", user: nil) }
    let!(:my_personal)    { create(:category, name: "My Home Food", user: user) }
    let!(:others_personal) { create(:category, name: "Others Bucket", user: other) }

    before { sign_in_as(user) }

    it "renders HTML successfully" do
      get categories_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "shows shared and user's own personal category names" do
      get categories_path
      expect(response.body).to include("Shared1")
      expect(response.body).to include("My Home Food")
    end

    it "does not expose another user's personal category names" do
      get categories_path
      expect(response.body).not_to include("Others Bucket")
    end
  end

  describe "GET /categories/:id", :integration do
    let!(:user)  { create(:user, email: "show_user@example.com") }
    let!(:other) { create(:user, email: "show_other@example.com") }
    let!(:shared_cat)      { create(:category, name: "ShownShared", user: nil) }
    let!(:own_personal)    { create(:category, name: "OwnPersonal", user: user) }
    let!(:others_personal) { create(:category, name: "OthersPersonal", user: other) }

    before { sign_in_as(user) }

    it "shows a shared category" do
      get category_path(shared_cat)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ShownShared")
    end

    it "shows own personal category" do
      get category_path(own_personal)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OwnPersonal")
    end

    it "returns 404 for another user's personal category (no existence leak)" do
      get category_path(others_personal)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /categories/new", :integration do
    let!(:user) { create(:user, email: "new_user@example.com") }

    before { sign_in_as(user) }

    it "renders the new form" do
      get new_category_path
      expect(response).to have_http_status(:ok)
    end

    it "requires authentication" do
      delete logout_path
      get new_category_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "POST /categories", :integration do
    let!(:user)  { create(:user, email: "create_user@example.com") }
    let!(:shared_parent) { create(:category, name: "CreateParentShared", user: nil) }

    before { sign_in_as(user) }

    it "creates a personal top-level category owned by current_user" do
      expect {
        post categories_path, params: {
          category: { name: "PersonalTop", color: "#ABCDEF" }
        }
      }.to change { user.reload; Category.personal_for(user).count }.by(1)

      created = Category.personal_for(user).find_by(name: "PersonalTop")
      expect(created).not_to be_nil
      expect(created.user_id).to eq(user.id)
      expect(response).to redirect_to(category_path(created))
    end

    it "creates a personal subcategory under a shared parent" do
      post categories_path, params: {
        category: { name: "PersonalChild", parent_id: shared_parent.id }
      }
      created = Category.find_by(name: "PersonalChild")
      expect(created).not_to be_nil
      expect(created.parent_id).to eq(shared_parent.id)
      expect(created.user_id).to eq(user.id)
    end

    it "ignores an attempt to set user_id in params (forces current_user)" do
      other = create(:user, email: "impersonate_target@example.com")
      post categories_path, params: {
        category: { name: "ImpersonationAttempt", user_id: other.id }
      }
      created = Category.find_by(name: "ImpersonationAttempt")
      expect(created).not_to be_nil
      expect(created.user_id).to eq(user.id)
      expect(created.user_id).not_to eq(other.id)
    end

    it "re-renders new on validation failure without creating" do
      expect {
        post categories_path, params: {
          category: { name: "", color: "not-a-hex" }
        }
      }.not_to change { Category.count }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 when parent_id points at another user's personal category" do
      other = create(:user, email: "sneaky_parent@example.com")
      others_personal = create(:category, name: "SneakyParent", user: other)

      expect {
        post categories_path, params: {
          category: { name: "TryCrossParent", parent_id: others_personal.id }
        }
      }.not_to change { Category.count }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when parent_id points at a nonexistent category" do
      expect {
        post categories_path, params: {
          category: { name: "TryMissingParent", parent_id: 9_999_999 }
        }
      }.not_to change { Category.count }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /categories/:id/edit", :integration do
    let!(:user)  { create(:user, email: "edit_user@example.com") }
    let!(:other) { create(:user, email: "edit_other@example.com") }
    let!(:own)      { create(:category, name: "EditOwn", user: user) }
    let!(:shared_c) { create(:category, name: "EditShared", user: nil) }
    let!(:others)   { create(:category, name: "EditOthers", user: other) }

    before { sign_in_as(user) }

    it "renders edit for owned personal" do
      get edit_category_path(own)
      expect(response).to have_http_status(:ok)
    end

    it "redirects with alert when trying to edit a shared category as non-admin" do
      get edit_category_path(shared_c)
      expect(response).to have_http_status(:found).or have_http_status(:see_other)
    end

    it "returns 404 when trying to edit another user's personal category" do
      get edit_category_path(others)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /categories/:id", :integration do
    let!(:user) { create(:user, email: "update_user@example.com") }
    let!(:own)  { create(:category, name: "OriginalName", user: user) }

    before { sign_in_as(user) }

    it "updates allowed attributes" do
      patch category_path(own), params: {
        category: { name: "NewName", color: "#112233" }
      }
      expect(response).to redirect_to(category_path(own))
      own.reload
      expect(own.name).to eq("NewName")
      expect(own.color).to eq("#112233")
    end

    it "ignores user_id in params (cannot change ownership via update)" do
      target = create(:user, email: "update_target@example.com")
      patch category_path(own), params: {
        category: { user_id: target.id }
      }
      own.reload
      expect(own.user_id).to eq(user.id)
    end

    it "re-renders edit on validation failure" do
      patch category_path(own), params: { category: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 when updating another user's personal category" do
      other = create(:user, email: "update_other@example.com")
      theirs = create(:category, name: "Theirs", user: other)
      patch category_path(theirs), params: { category: { name: "Hijack" } }
      expect(response).to have_http_status(:not_found)
      theirs.reload
      expect(theirs.name).to eq("Theirs")
    end
  end

  describe "DELETE /categories/:id", :integration do
    let!(:user) { create(:user, email: "delete_user@example.com") }

    before { sign_in_as(user) }

    it "destroys an empty personal category" do
      victim = create(:category, name: "Victim", user: user)
      expect { delete category_path(victim) }.to change { Category.count }.by(-1)
      expect(response).to redirect_to(categories_path)
    end

    it "refuses to destroy a category that is in use by expenses (deferred to PR 8)" do
      victim = create(:category, name: "Occupied", user: user)
      email_account = create(:email_account, user: user)
      create(:expense, category: victim, email_account: email_account)

      expect { delete category_path(victim) }.not_to change { Category.count }
      expect(response).to have_http_status(:unprocessable_entity).or redirect_to(category_path(victim))
    end

    it "returns 404 on another user's personal category" do
      other = create(:user, email: "delete_other@example.com")
      theirs = create(:category, name: "Theirs2", user: other)
      expect { delete category_path(theirs) }.not_to change { Category.count }
      expect(response).to have_http_status(:not_found)
    end

    it "refuses destroy when the category has children" do
      victim = create(:category, name: "WithChild", user: user)
      create(:category, name: "Child of WithChild", user: user, parent: victim)
      expect { delete category_path(victim) }.not_to change { Category.count }
      expect(response).to redirect_to(category_path(victim))
    end

    it "refuses destroy when the category has categorization_patterns" do
      victim = create(:category, name: "WithPattern", user: user)
      create(:categorization_pattern, category: victim, pattern_type: "merchant", pattern_value: "somestore")
      expect { delete category_path(victim) }.not_to change { Category.count }
      expect(response).to redirect_to(category_path(victim))
    end

    it "refuses destroy when the category has user_category_preferences" do
      victim = create(:category, name: "WithPref", user: user)
      email_account = create(:email_account, user: user)
      create(:user_category_preference,
             email_account: email_account,
             category: victim,
             context_type: "merchant",
             context_value: "foo",
             preference_weight: 1,
             usage_count: 1)
      expect { delete category_path(victim) }.not_to change { Category.count }
      expect(response).to redirect_to(category_path(victim))
    end
  end

  describe "admin paths", :integration do
    let!(:admin_current) { create(:user, :admin, email: "admin_current@example.com") }
    let!(:other)         { create(:user, email: "admin_other@example.com") }
    let!(:shared_c)      { create(:category, name: "AdminCanEditShared", user: nil) }
    let!(:others_personal) { create(:category, name: "AdminCanEditOthers", user: other) }

    before { sign_in_as(admin_current) }

    it "admin can edit a shared category" do
      get edit_category_path(shared_c)
      expect(response).to have_http_status(:ok)
    end

    it "admin can update another user's personal category" do
      patch category_path(others_personal), params: { category: { color: "#123456" } }
      expect(response).to redirect_to(category_path(others_personal))
      others_personal.reload
      expect(others_personal.color).to eq("#123456")
    end

    it "admin can destroy an empty shared category" do
      victim = create(:category, name: "AdminDeleteShared", user: nil)
      expect { delete category_path(victim) }.to change { Category.count }.by(-1)
    end
  end
end
