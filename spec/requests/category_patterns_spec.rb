# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Category Patterns", type: :request, integration: true do
  let!(:user)  { create(:user, email: "cp_user@example.com") }
  let!(:other) { create(:user, email: "cp_other@example.com") }

  let!(:own)      { create(:category, name: "CP_Own", user: user) }
  let!(:shared_c) { create(:category, name: "CP_Shared", user: nil) }
  let!(:others)   { create(:category, name: "CP_Others", user: other) }

  describe "POST /categories/:category_id/patterns" do
    before { sign_in_as(user) }

    it "adds a pattern to a user's own personal category" do
      expect {
        post category_patterns_path(own), params: {
          categorization_pattern: { pattern_type: "merchant", pattern_value: "mcdonalds" }
        }
      }.to change { own.categorization_patterns.count }.by(1)

      created = own.categorization_patterns.last
      expect(created.pattern_type).to eq("merchant")
      expect(created.pattern_value).to eq("mcdonalds")
      expect(created.user_created).to be true
      expect(response).to redirect_to(category_path(own))
    end

    it "rejects adding a pattern to a shared category (non-admin)" do
      expect {
        post category_patterns_path(shared_c), params: {
          categorization_pattern: { pattern_type: "merchant", pattern_value: "x" }
        }
      }.not_to change { CategorizationPattern.count }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when trying to add a pattern to another user's personal category (no existence leak)" do
      expect {
        post category_patterns_path(others), params: {
          categorization_pattern: { pattern_type: "merchant", pattern_value: "x" }
        }
      }.not_to change { CategorizationPattern.count }
      expect(response).to have_http_status(:not_found)
    end

    it "re-renders the category show with errors on validation failure" do
      expect {
        post category_patterns_path(own), params: {
          categorization_pattern: { pattern_type: "invalid_type", pattern_value: "x" }
        }
      }.not_to change { CategorizationPattern.count }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires authentication" do
      delete logout_path
      post category_patterns_path(own), params: {
        categorization_pattern: { pattern_type: "merchant", pattern_value: "x" }
      }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "DELETE /categories/:category_id/patterns/:id" do
    let!(:pattern) {
      create(:categorization_pattern,
             category: own,
             pattern_type: "merchant",
             pattern_value: "target_pattern")
    }

    before { sign_in_as(user) }

    it "deletes a pattern belonging to the user's own category" do
      expect {
        delete category_pattern_path(own, pattern)
      }.to change { own.categorization_patterns.count }.by(-1)
      expect(response).to redirect_to(category_path(own))
    end

    it "refuses to delete a pattern via another user's category scope" do
      expect {
        delete category_pattern_path(others, pattern)
      }.not_to change { CategorizationPattern.count }
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to delete a pattern via a shared category as non-admin" do
      shared_pattern = create(:categorization_pattern,
                              category: shared_c,
                              pattern_type: "merchant",
                              pattern_value: "shared_pattern")
      expect {
        delete category_pattern_path(shared_c, shared_pattern)
      }.not_to change { CategorizationPattern.count }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "admin paths" do
    let!(:admin_current) { create(:user, :admin, email: "cp_admin@example.com") }
    let!(:others_pattern) {
      create(:categorization_pattern,
             category: others,
             pattern_type: "merchant",
             pattern_value: "cross_user_target")
    }

    before { sign_in_as(admin_current) }

    it "admin can add a pattern to a shared category" do
      expect {
        post category_patterns_path(shared_c), params: {
          categorization_pattern: { pattern_type: "merchant", pattern_value: "admin_added" }
        }
      }.to change { shared_c.categorization_patterns.count }.by(1)
    end

    it "admin can delete a pattern on another user's category" do
      expect {
        delete category_pattern_path(others, others_pattern)
      }.to change { CategorizationPattern.count }.by(-1)
    end
  end

  describe "show view patterns section" do
    before { sign_in_as(user) }

    it "renders patterns list + add form for a category the user can manage" do
      create(:categorization_pattern,
             category: own,
             pattern_type: "merchant",
             pattern_value: "listed_value",
             usage_count: 7,
             success_count: 5)
      get category_path(own)
      expect(response.body).to include("listed_value")
      expect(response.body).to include("Patterns")
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("form[action='#{category_patterns_path(own)}']")).not_to be_nil
    end

    it "does not render the add form for read-only categories" do
      get category_path(shared_c)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("form[action='#{category_patterns_path(shared_c)}']")).to be_nil
    end
  end
end
