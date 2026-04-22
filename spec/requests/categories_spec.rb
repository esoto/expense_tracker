# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories API", type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:category_food) { create(:category, name: "Food", color: "#FF6B6B") }
  let!(:category_transport) { create(:category, name: "Transport", color: "#4ECDC4") }

  # PR 10: most examples exercise the write surface and predate the
  # feature flag — treat the flag as on by default, and let the one
  # describe that tests the gate unset it explicitly.
  before do
    ENV["PERSONAL_CATEGORIES_OPEN_TO_ALL"] = "true"
  end

  after do
    ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL")
  end

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

    context "tree structure" do
      let!(:shared_root)       { create(:category, name: "TreeSharedRoot", user: nil) }
      let!(:shared_child)      { create(:category, name: "TreeSharedChild", user: nil, parent: shared_root) }
      let!(:personal_subchild) { create(:category, name: "TreeMyPersonalSub", user: user, parent: shared_root) }
      let!(:personal_branch)   { create(:category, name: "TreeMyPersonalBranch", user: user) }
      let!(:other_personal_under_shared) {
        create(:category, name: "TreeOthersSub", user: other, parent: shared_root)
      }

      before { get categories_path }

      it "renders a Shared heading and a My Categories heading" do
        expect(response.body).to include("Shared")
        expect(response.body).to include("My Categories")
      end

      # Parse the DOM once and scope assertions to the Shared vs My
      # Categories sections so a regression in tree placement produces a
      # meaningful failure (not just a substring-index mismatch).
      let(:doc) { Nokogiri::HTML(response.body) }
      # The two column <section>s carry the `bg-white` class; the outer
      # container does not. Scoping to that class keeps the h2 text match
      # from matching the outer wrapper (which transitively contains both
      # column headings via descendants).
      let(:shared_section) do
        doc.css("section.bg-white").find { |s| s.at_css("h2")&.text&.include?("Shared") }
      end
      let(:personal_section) do
        doc.css("section.bg-white").find { |s| s.at_css("h2")&.text&.include?("My Categories") }
      end

      it "renders the user's personal subcategory under its shared parent" do
        expect(shared_section).not_to be_nil
        expect(shared_section.text).to include("TreeSharedRoot")
        expect(shared_section.text).to include("TreeMyPersonalSub")
      end

      it "renders the user's personal top-level branch in the My Categories column" do
        expect(personal_section).not_to be_nil
        expect(personal_section.text).to include("TreeMyPersonalBranch")
      end

      it "does not place personal top-level branch in the Shared column" do
        expect(shared_section.text).not_to include("TreeMyPersonalBranch")
      end

      it "hides another user's personal subcategory even when it lives under a shared parent" do
        expect(response.body).not_to include("TreeOthersSub")
      end

      it "renders shared children under shared parents" do
        expect(shared_section.text).to include("TreeSharedChild")
      end
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

    context "with a ?parent_id= prefill (inline + Add subcategory flow)" do
      let!(:shared_parent) { create(:category, name: "PrefillShared", user: nil) }

      it "preselects the shared parent in the form select" do
        get new_category_path(parent_id: shared_parent.id)
        expect(response).to have_http_status(:ok)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="category[parent_id]"] option[selected]')
        expect(selected&.attr("value")).to eq(shared_parent.id.to_s)
      end

      it "preselects the user's own personal category as a parent" do
        own = create(:category, name: "PrefillOwnPersonal", user: user)
        get new_category_path(parent_id: own.id)
        doc = Nokogiri::HTML(response.body)
        selected = doc.at_css('select[name="category[parent_id]"] option[selected]')
        expect(selected&.attr("value")).to eq(own.id.to_s)
      end

      it "silently drops a parent_id pointing at another user's personal category" do
        other = create(:user, email: "prefill_other@example.com")
        others = create(:category, name: "OthersPrefill", user: other)
        get new_category_path(parent_id: others.id)
        expect(response).to have_http_status(:ok)
        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css('select[name="category[parent_id]"] option[selected]')).to be_nil
      end

      it "silently drops a parent_id that does not exist" do
        get new_category_path(parent_id: 9_999_999)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "Turbo Frame side panel (PR 6)", :integration do
    let!(:user) { create(:user, email: "frame_user@example.com") }
    let!(:own)  { create(:category, name: "FrameOwn", user: user) }

    before { sign_in_as(user) }

    it "index renders the category_panel frame placeholder" do
      get categories_path
      expect(response.body).to match(/turbo-frame[^>]+id="category_panel"/)
      expect(response.body).to include("Select a category to see details")
    end

    it "show wraps content in the category_panel frame" do
      get category_path(own)
      doc = Nokogiri::HTML(response.body)
      frame = doc.at_css('turbo-frame#category_panel')
      expect(frame).not_to be_nil
      expect(frame.text).to include("FrameOwn")
    end

    it "edit wraps the form in the same frame" do
      get edit_category_path(own)
      doc = Nokogiri::HTML(response.body)
      frame = doc.at_css('turbo-frame#category_panel')
      expect(frame).not_to be_nil
      form = frame.at_css("form")
      expect(form).not_to be_nil
      expect(form.at_css('input[name="category[name]"]')&.attr("value")).to eq("FrameOwn")
    end

    it "new wraps the form in the same frame" do
      get new_category_path
      doc = Nokogiri::HTML(response.body)
      frame = doc.at_css('turbo-frame#category_panel')
      expect(frame).not_to be_nil
      expect(frame.at_css("form")).not_to be_nil
    end

    it "index tree links carry the frame target data attribute" do
      get categories_path
      doc = Nokogiri::HTML(response.body)
      tree_link = doc.at_css('a[data-turbo-frame="category_panel"]')
      expect(tree_link).not_to be_nil
    end

    it "updating within the frame redirects to show (which is framed)" do
      patch category_path(own), params: { category: { name: "Renamed" } },
            headers: { "Turbo-Frame" => "category_panel" }
      # Controller redirects; follow manually to confirm final response is framed.
      follow_redirect!
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('turbo-frame#category_panel')).not_to be_nil
      expect(doc.at_css('turbo-frame#category_panel').text).to include("Renamed")
    end

    it "the 'Open full page' link breaks out of the frame via _top" do
      get category_path(own)
      doc = Nokogiri::HTML(response.body)
      link = doc.at_css('a[data-turbo-frame="_top"]')
      expect(link).not_to be_nil
      expect(link.text).to include("Open full page")
    end

    it "destroy from within the frame redirects to the index placeholder" do
      delete category_path(own), headers: { "Turbo-Frame" => "category_panel" }
      follow_redirect!
      doc = Nokogiri::HTML(response.body)
      # After destroy, the panel on /categories renders the empty-state
      # placeholder we put in the frame.
      expect(doc.at_css('turbo-frame#category_panel').text).to include("Select a category to see details")
    end

    it "creating within the frame redirects into a framed show" do
      post categories_path, params: { category: { name: "CreatedInFrame" } },
           headers: { "Turbo-Frame" => "category_panel" }
      follow_redirect!
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('turbo-frame#category_panel')).not_to be_nil
      expect(doc.at_css('turbo-frame#category_panel').text).to include("CreatedInFrame")
    end
  end

  describe "inline '+ Add subcategory' affordance on shared roots", :integration do
    let!(:user) { create(:user, email: "affordance_user@example.com") }
    let!(:shared_root)  { create(:category, name: "AffordShared", user: nil) }
    let!(:shared_child) { create(:category, name: "AffordSharedChild", user: nil, parent: shared_root) }
    let!(:personal_root) { create(:category, name: "AffordPersonal", user: user) }

    before { sign_in_as(user) }

    it "shows an Add subcategory link on shared root rows" do
      get categories_path
      doc = Nokogiri::HTML(response.body)
      links = doc.css("a").select { |a| a.text.include?("Add subcategory") && a["href"] =~ /parent_id=#{shared_root.id}/ }
      expect(links).not_to be_empty
    end

    it "does not show Add subcategory on shared children (only on roots)" do
      get categories_path
      doc = Nokogiri::HTML(response.body)
      # Find the tree-node row for the shared child and make sure it has no affordance.
      link = doc.css("a").find { |a| a.text.include?("Add subcategory") && a["href"] =~ /parent_id=#{shared_child.id}/ }
      expect(link).to be_nil
    end

    it "does not show Add subcategory on personal roots" do
      get categories_path
      doc = Nokogiri::HTML(response.body)
      link = doc.css("a").find { |a| a.text.include?("Add subcategory") && a["href"] =~ /parent_id=#{personal_root.id}/ }
      expect(link).to be_nil
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

    it "deletes a personal category with expenses via :orphan by default" do
      victim = create(:category, name: "Occupied", user: user)
      email_account = create(:email_account, user: user)
      expense = create(:expense, category: victim, email_account: email_account)

      expect { delete category_path(victim) }.to change { Category.count }.by(-1)
      expect(expense.reload.category_id).to be_nil
      expect(response).to redirect_to(categories_path)
    end

    it "deletes a personal category via :reassign when strategy+target are provided" do
      victim = create(:category, name: "ReassignSource", user: user)
      target = create(:category, name: "ReassignTarget", user: user)
      email_account = create(:email_account, user: user)
      expense = create(:expense, category: victim, email_account: email_account)

      delete category_path(victim), params: { strategy: "reassign", reassign_to_id: target.id }
      expect(Category.exists?(victim.id)).to be false
      expect(expense.reload.category_id).to eq(target.id)
    end

    it "keeps the category and surfaces error when reassign is chosen without a target" do
      victim = create(:category, name: "NoTarget", user: user)
      email_account = create(:email_account, user: user)
      create(:expense, category: victim, email_account: email_account)

      delete category_path(victim), params: { strategy: "reassign" }
      expect(Category.exists?(victim.id)).to be true
      expect(response).to redirect_to(category_path(victim))
    end

    it "returns 404 on another user's personal category" do
      other = create(:user, email: "delete_other@example.com")
      theirs = create(:category, name: "Theirs2", user: other)
      expect { delete category_path(theirs) }.not_to change { Category.count }
      expect(response).to have_http_status(:not_found)
    end

    it "deletes a personal category with children via :orphan (children detach)" do
      victim = create(:category, name: "WithChild", user: user)
      child = create(:category, name: "Child of WithChild", user: user, parent: victim)
      expect { delete category_path(victim) }.to change { Category.count }.by(-1)
      expect(child.reload.parent_id).to be_nil
    end

    it "deletes a personal category with patterns via :orphan (patterns cascade)" do
      victim = create(:category, name: "WithPattern", user: user)
      create(:categorization_pattern, category: victim, pattern_type: "merchant", pattern_value: "somestore")
      expect {
        delete category_path(victim)
      }.to change { Category.count }.by(-1).and change { CategorizationPattern.count }.by(-1)
    end
  end

  describe "GET /categories/:id/confirm_delete", :integration do
    let!(:user) { create(:user, email: "confirm_user@example.com") }

    before { sign_in_as(user) }

    it "renders the reassign/orphan chooser for a category with dependents" do
      victim = create(:category, name: "ConfirmVictim", user: user)
      email_account = create(:email_account, user: user)
      create(:expense, category: victim, email_account: email_account)

      get confirm_delete_category_path(victim)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Orphan")
      expect(response.body).to include("Reassign")
    end

    it "returns 404 for another user's personal category" do
      other = create(:user, email: "confirm_other@example.com")
      theirs = create(:category, name: "NotYoursConfirm", user: other)
      get confirm_delete_category_path(theirs)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "feature flag (PR 10)", :integration do
    let!(:regular) { create(:user, email: "flag_regular@example.com") }

    before { sign_in_as(regular) }

    context "when the flag is off" do
      # The outer before block sets the flag on by default. Flip it off
      # for this context via an after-all setup. The nested-hook ordering
      # guarantees this before runs AFTER the outer "set flag on" before.
      before { ENV.delete("PERSONAL_CATEGORIES_OPEN_TO_ALL") }

      it "GET /categories/new redirects" do
        get new_category_path
        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(categories_path)
        follow_redirect!
        expect(response.body).to include("Personal category management isn&#39;t available")
      end

      it "POST /categories is blocked" do
        expect {
          post categories_path, params: { category: { name: "ShouldNotCreate" } }
        }.not_to change { Category.count }
        expect(response).to redirect_to(categories_path)
      end

      it "GET /categories still loads (read access is always open)" do
        get categories_path
        expect(response).to have_http_status(:ok)
      end

      it "does not render the 'New category' button" do
        get categories_path
        expect(response.body).not_to include("New category")
      end

      it "GET /categories/:id/confirm_delete redirects (write surface gated)" do
        own = create(:category, name: "FlagOffConfirm", user: regular)
        get confirm_delete_category_path(own)
        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(categories_path)
      end

      it "DELETE /categories/:id is blocked (write gate)" do
        own = create(:category, name: "FlagOffDestroy", user: regular)
        expect { delete category_path(own) }.not_to change { Category.count }
        expect(response).to redirect_to(categories_path)
      end
    end

    context "when flag is on (outer before sets it true)" do
      it "GET /categories/new renders normally" do
        get new_category_path
        expect(response).to have_http_status(:ok)
      end

      it "POST /categories creates as expected" do
        expect {
          post categories_path, params: { category: { name: "FlagEnabledCreate" } }
        }.to change { Category.count }.by(1)
      end

      it "renders the 'New category' button" do
        get categories_path
        expect(response.body).to include("New category")
      end
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

    it "admin deleting a shared category must provide a reassign target (design-doc rule)" do
      victim = create(:category, name: "AdminDeleteShared", user: nil)
      fallback = create(:category, name: "AdminDeleteFallback", user: nil)
      expect {
        delete category_path(victim), params: { strategy: "reassign", reassign_to_id: fallback.id }
      }.to change { Category.count }.by(-1)
    end

    it "admin deleting a shared category without a target surfaces the error" do
      victim = create(:category, name: "AdminDeleteSharedNoTarget", user: nil)
      expect { delete category_path(victim) }.not_to change { Category.count }
      expect(response).to redirect_to(category_path(victim))
    end
  end
end
