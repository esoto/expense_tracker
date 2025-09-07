# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RateLimiting, type: :controller, unit: true do
  controller(ApplicationController) do
    include RateLimiting
    include Authentication

    # Override the actions that the concern will apply rate limiting to
    def categorize
      render json: { message: 'categorize success' }
    end

    def auto_categorize
      render json: { message: 'auto_categorize success' }
    end

    def export
      render json: { message: 'export success' }
    end

    def suggest
      render json: { message: 'suggest success' }
    end
  end

  before do
    routes.draw do
      post 'categorize' => 'anonymous#categorize'
      post 'auto_categorize' => 'anonymous#auto_categorize'
      get 'export' => 'anonymous#export'
      post 'suggest' => 'anonymous#suggest'
    end

    # Clear any cached rate limits
    if defined?(Rails.cache)
      Rails.cache.clear
    end

    # Mock the rate limit store
    @store = RateLimiting::MemoryRateLimitStore.new
    allow(controller).to receive(:rate_limit_store).and_return(@store)
  end

  let!(:user) { create(:admin_user, email: "admin_#{SecureRandom.hex(4)}@example.com") }

  before do
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe "rate limit enforcement for categorize", unit: true do
    it "allows requests under the limit" do
      9.times { post :categorize, format: :json }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('categorize success')
    end

    it "blocks requests over the limit" do
      11.times { post :categorize, format: :json }
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['error']).to include('Rate limit exceeded')
    end
  end

  describe "rate limit enforcement for auto_categorize", unit: true do
    it "allows requests under the limit" do
      4.times { post :auto_categorize, format: :json }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('auto_categorize success')
    end

    it "blocks requests over the limit" do
      6.times { post :auto_categorize, format: :json }
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['error']).to include('Rate limit exceeded')
    end
  end

  describe "rate limit enforcement for export", unit: true do
    it "allows requests under the limit (hourly window)" do
      19.times { get :export, format: :json }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('export success')
    end

    it "blocks requests over the limit" do
      21.times { get :export, format: :json }
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['error']).to include('Rate limit exceeded')
    end
  end

  describe "rate limit enforcement for suggest", unit: true do
    it "allows requests under the limit" do
      14.times { post :suggest, format: :json }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('suggest success')
    end

    it "blocks requests over the limit" do
      16.times { post :suggest, format: :json }
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)['error']).to include('Rate limit exceeded')
    end
  end

  describe "rate limit keys", unit: true do
    it "generates unique keys per user" do
      key1 = controller.send(:rate_limit_key, :categorize)
      expect(key1).to eq("rate_limit:bulk_operations:#{user.id}:categorize")

      another_user = create(:admin_user, email: "another_#{SecureRandom.hex(4)}@example.com")
      allow(controller).to receive(:current_user).and_return(another_user)

      key2 = controller.send(:rate_limit_key, :categorize)
      expect(key2).to eq("rate_limit:bulk_operations:#{another_user.id}:categorize")
      expect(key1).not_to eq(key2)
    end

    it "generates different keys for different operations" do
      key1 = controller.send(:rate_limit_key, :categorize)
      key2 = controller.send(:rate_limit_key, :export)

      expect(key1).not_to eq(key2)
      expect(key1).to include('categorize')
      expect(key2).to include('export')
    end
  end

  describe "MemoryRateLimitStore", unit: true do
    let(:store) { RateLimiting::MemoryRateLimitStore.new }

    it "stores and retrieves values" do
      store.setex("test_key", 60, 5)
      expect(store.get("test_key")).to eq(5)
    end

    it "increments values" do
      store.setex("test_key", 60, 1)
      store.incr("test_key")
      expect(store.get("test_key")).to eq(2)
    end

    it "checks key existence" do
      expect(store.exists?("nonexistent")).to be false
      store.setex("test_key", 60, 1)
      expect(store.exists?("test_key")).to be true
    end

    it "returns 0 for non-existent keys" do
      expect(store.get("nonexistent")).to eq(0)
    end
  end

  describe "error response formats", unit: true do
    before do
      # Exhaust the rate limit
      11.times { post :categorize, format: :json }
    end

    it "returns proper JSON error structure" do
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('error')
      expect(json_response).to have_key('limit')
      expect(json_response).to have_key('window')
      expect(json_response['limit']).to eq(10)
      expect(json_response['window']).to eq("1 minutes")
    end
  end
end
