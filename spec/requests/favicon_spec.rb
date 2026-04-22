# frozen_string_literal: true

require "rails_helper"

# Browsers auto-request `/favicon.ico` regardless of the <link rel="icon">
# tags in the layout. Before the redirect in config/routes.rb, that request
# 404'd — which kept stale red-dot favicons pinned in browser caches long
# after the teal bar-chart replacement shipped. Keep this test green so the
# redirect doesn't silently regress during a routes refactor.
RSpec.describe "favicon", type: :request do
  describe "GET /favicon.ico", :unit do
    it "redirects to /icon.svg with a 301 (Moved Permanently)" do
      get "/favicon.ico"
      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to end_with("/icon.svg")
    end
  end
end
