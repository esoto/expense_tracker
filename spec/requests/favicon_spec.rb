# frozen_string_literal: true

require "rails_helper"

# Browsers auto-request `/favicon.ico` and (on Safari/iOS) `/apple-touch-icon*.png`
# regardless of the <link rel="icon"> tags in the layout. Before the redirects
# in config/routes.rb, those requests 404'd — which kept stale red-dot favicons
# pinned in browser caches long after the teal bar-chart replacement shipped.
# Keep these tests green so a future routes refactor doesn't silently regress.
RSpec.describe "favicon", type: :request do
  describe "GET /favicon.ico", :unit do
    it "redirects to /icon.png with a 301 (Moved Permanently)" do
      get "/favicon.ico"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/icon.png")
    end
  end

  describe "GET /apple-touch-icon.png", :unit do
    it "redirects to /icon.png with a 301" do
      get "/apple-touch-icon.png"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/icon.png")
    end
  end

  describe "GET /apple-touch-icon-precomposed.png", :unit do
    it "redirects to /icon.png with a 301" do
      get "/apple-touch-icon-precomposed.png"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/icon.png")
    end
  end
end
