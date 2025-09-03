# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RateLimiting, type: :controller, unit: true do
  controller(ApplicationController) do
    include RateLimiting

    rate_limit :index, limit: 5, period: 1.minute, by: :ip
    rate_limit :create, limit: 3, period: 1.hour, by: :user
    rate_limit :show, limit: 10, period: 5.minutes, by: :session

    def index
      render json: { message: 'success' }
    end

    def create
      render json: { message: 'created' }
    end

    def show
      render json: { message: 'show' }
    end

    private

    def current_user
      @current_user ||= AdminUser.find_or_create_by(email: 'test@example.com') do |user|
        user.password = 'password'
        user.role = 'admin'
      end
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      post 'create' => 'anonymous#create'
      get 'show' => 'anonymous#show'
    end
    Rails.cache.clear
  end

  let!(:user) { create(:admin_user, email: "admin_#{SecureRandom.hex(4)}@example.com") }

  # Use shared examples for standard rate limiting behavior
  it_behaves_like "rate limiting concern"

  describe "rate limit enforcement", unit: true do
    it "allows requests under the limit" do
      3.times { get :index }
      expect(response).to have_http_status(:ok)
    end

    it "blocks JSON requests over the limit" do
      6.times { get :index, format: :json }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns appropriate JSON error when limit exceeded" do
      6.times { get :index, format: :json }

      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Rate limit exceeded')
      expect(json_response['limit']).to eq(5)
      expect(json_response['retry_after']).to eq(60)
    end

    it "redirects HTML requests when limit exceeded" do
      6.times { get :index }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('Too many requests')
    end
  end

  describe "different rate limiting strategies", unit: true do
    it "enforces user-based rate limiting" do
      allow(controller).to receive(:current_user).and_return(user)

      4.times { post :create, format: :json }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "enforces session-based rate limiting" do
      11.times { get :show, format: :json }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "generates different rate limit keys for different IPs" do
      key1 = controller.send(:rate_limit_key, :index, :ip)

      allow(controller.request).to receive(:remote_ip).and_return('192.168.1.2')
      key2 = controller.send(:rate_limit_key, :index, :ip)

      expect(key1).not_to eq(key2)
      expect(key1).to include('0.0.0.0')
      expect(key2).to include('192.168.1.2')
    end
  end

  describe "#rate_limit_key", unit: true do
    it "generates correct key for IP-based limiting" do
      allow(controller.request).to receive(:remote_ip).and_return('127.0.0.1')

      key = controller.send(:rate_limit_key, :index, :ip)
      expect(key).to eq("rate_limit:anonymous:index:127.0.0.1")
    end

    it "generates correct key for user-based limiting" do
      allow(controller).to receive(:current_user).and_return(user)

      key = controller.send(:rate_limit_key, :create, :user)
      expect(key).to eq("rate_limit:anonymous:create:#{user.id}")
    end

    it "handles anonymous user for user-based limiting" do
      allow(controller).to receive(:current_user).and_return(nil)

      key = controller.send(:rate_limit_key, :create, :user)
      expect(key).to eq("rate_limit:anonymous:create:anonymous")
    end
  end

  describe "#rate_limit_remaining", unit: true do
    it "returns correct remaining count" do
      2.times { get :index }

      remaining = controller.send(:rate_limit_remaining, :index)
      expect(remaining).to eq(3)
    end

    it "returns 0 when limit is exceeded" do
      6.times { get :index }

      remaining = controller.send(:rate_limit_remaining, :index)
      expect(remaining).to eq(0)
    end

    it "returns nil for undefined actions" do
      remaining = controller.send(:rate_limit_remaining, :undefined)
      expect(remaining).to be_nil
    end
  end

  describe "#reset_rate_limit", unit: true do
    it "resets rate limit for current user" do
      5.times { get :index, format: :json }
      expect(response).to have_http_status(:ok)

      get :index, format: :json
      expect(response).to have_http_status(:too_many_requests)

      controller.send(:reset_rate_limit, :index)

      get :index, format: :json
      expect(response).to have_http_status(:ok)
    end

    it "can reset rate limit for specific identifier" do
      ip_address = '192.168.1.100'
      result = controller.send(:reset_rate_limit, :index, ip_address)
      expect(result).to be true
    end

    it "returns false for undefined actions" do
      result = controller.send(:reset_rate_limit, :undefined)
      expect(result).to be false
    end
  end

  describe "logging", unit: true do
    it "logs rate limit violations" do
      allow(Rails.logger).to receive(:warn)

      6.times { get :index, format: :json }

      expect(Rails.logger).to have_received(:warn).with(
        include('"event":"rate_limit_exceeded"')
      )
    end
  end
end
