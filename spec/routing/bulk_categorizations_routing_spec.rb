# frozen_string_literal: true

require "rails_helper"

# PER-229: Regression guard — export.csv must route to #export, NOT #show
RSpec.describe "BulkCategorizations routing", :unit, type: :routing do
  describe "GET /bulk_categorizations/export" do
    it "routes to bulk_categorization_actions#export" do
      expect(get: "/bulk_categorizations/export").to route_to(
        controller: "bulk_categorization_actions",
        action: "export"
      )
    end

    it "routes export.csv to bulk_categorization_actions#export (not #show with id='export')" do
      expect(get: "/bulk_categorizations/export.csv").to route_to(
        controller: "bulk_categorization_actions",
        action: "export",
        format: "csv"
      )
    end

    it "does NOT route export to bulk_categorizations#show" do
      expect(get: "/bulk_categorizations/export").not_to route_to(
        controller: "bulk_categorizations",
        action: "show",
        id: "export"
      )
    end
  end

  describe "POST /bulk_categorizations/categorize" do
    it "routes to bulk_categorization_actions#categorize (not #show)" do
      expect(post: "/bulk_categorizations/categorize").to route_to(
        controller: "bulk_categorization_actions",
        action: "categorize"
      )
    end
  end

  describe "GET /bulk_categorizations/:id" do
    it "routes to bulk_categorizations#show for numeric ids" do
      expect(get: "/bulk_categorizations/1").to route_to(
        controller: "bulk_categorizations",
        action: "show",
        id: "1"
      )
    end
  end
end
