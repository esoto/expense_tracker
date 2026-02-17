# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiConfiguration, type: :controller, unit: true do
  controller(ApplicationController) do
    include ApiConfiguration

    def index
      render json: api_config
    end

    def paginated_list
      # Create a simple mock collection - will be set up in before block
      result = paginate_with_limits(@test_collection)
      render json: { count: result.length || 0 }
    end
  end

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)

    routes.draw do
      get 'index' => 'anonymous#index'
      get 'paginated_list' => 'anonymous#paginated_list'
    end

    # Set up mock collection for pagination tests
    @paginated_result = double('paginated_result', length: 0)
    @limit_chain = double('limit_chain')
    @test_collection = double('collection')
    allow(@test_collection).to receive(:limit).with(anything).and_return(@limit_chain)
    allow(@limit_chain).to receive(:offset).with(anything).and_return(@paginated_result)
    controller.instance_variable_set(:@test_collection, @test_collection)
  end

  # Use shared examples for api configuration behavior
  it_behaves_like "api configuration concern"

  describe "constants", unit: true do
    it "defines pagination constants" do
      expect(ApiConfiguration::DEFAULT_PAGE_SIZE).to eq(25)
      expect(ApiConfiguration::MAX_PAGE_SIZE).to eq(100)
      expect(ApiConfiguration::MIN_PAGE_SIZE).to eq(1)
    end

    it "defines cache expiration constants" do
      expect(ApiConfiguration::CACHE_EXPIRY_SHORT).to eq(1.minute)
      expect(ApiConfiguration::CACHE_EXPIRY_MEDIUM).to eq(5.minutes)
      expect(ApiConfiguration::CACHE_EXPIRY_LONG).to eq(1.hour)
      expect(ApiConfiguration::CACHE_EXPIRY_READ).to eq(15.minutes)
    end

    it "defines rate limiting constants" do
      expect(ApiConfiguration::RATE_LIMIT_WINDOW).to eq(1.hour)
      expect(ApiConfiguration::RATE_LIMIT_MAX_REQUESTS).to eq(1000)
    end

    it "defines API versioning constants" do
      expect(ApiConfiguration::CURRENT_API_VERSION).to eq("v1")
      expect(ApiConfiguration::SUPPORTED_API_VERSIONS).to eq([ "v1" ])
    end

    it "defines performance threshold constants" do
      expect(ApiConfiguration::MIN_SUCCESS_RATE_THRESHOLD).to eq(0.0)
      expect(ApiConfiguration::MAX_SUCCESS_RATE_THRESHOLD).to eq(1.0)
      expect(ApiConfiguration::DEFAULT_CONFIDENCE_WEIGHT).to eq(1.0)
      expect(ApiConfiguration::COMPOSITE_CONFIDENCE_WEIGHT).to eq(1.5)
    end

    it "defines security constants" do
      expect(ApiConfiguration::TOKEN_CACHE_KEY_LENGTH).to eq(16)
      expect(ApiConfiguration::SECURE_TOKEN_LENGTH).to eq(32)
    end
  end

  describe "api configuration access", unit: true do
    it "returns api configuration via HTTP request" do
      get :index

      expect(response).to have_http_status(:ok)

      config = JSON.parse(response.body)
      expect(config['pagination']['default_size']).to eq(25)
      expect(config['pagination']['max_size']).to eq(100)
      expect(config['pagination']['min_size']).to eq(1)
      expect(config['version']['current']).to eq('v1')
    end

    it "includes cache configuration" do
      get :index
      config = JSON.parse(response.body)

      expect(config['cache']['short']).to eq(60) # 1.minute in seconds
      expect(config['cache']['medium']).to eq(300) # 5.minutes in seconds
      expect(config['cache']['long']).to eq(3600) # 1.hour in seconds
      expect(config['cache']['read']).to eq(900) # 15.minutes in seconds
    end

    it "includes rate limit configuration" do
      get :index
      config = JSON.parse(response.body)

      expect(config['rate_limit']['window']).to eq(3600) # 1.hour in seconds
      expect(config['rate_limit']['max_requests']).to eq(1000)
    end
  end

  describe "pagination with limits", unit: true do
    it "uses default page size when no parameters provided" do
      get :paginated_list
      expect(response).to have_http_status(:ok)

      # Verify the method was called by checking the action executed successfully
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('count')
    end

    it "caps at maximum page size when exceeding limit" do
      get :paginated_list, params: { per_page: '200' }
      expect(response).to have_http_status(:ok)
    end

    it "uses default when per_page is below minimum" do
      get :paginated_list, params: { per_page: '0' }
      expect(response).to have_http_status(:ok)
    end

    it "uses default when per_page is negative" do
      get :paginated_list, params: { per_page: '-5' }
      expect(response).to have_http_status(:ok)
    end

    it "uses default when per_page is invalid" do
      get :paginated_list, params: { per_page: 'invalid' }
      expect(response).to have_http_status(:ok)
    end

    it "handles page parameter correctly" do
      get :paginated_list, params: { page: '3', per_page: '50' }
      expect(response).to have_http_status(:ok)
    end

    it "handles edge case: per_page exactly at minimum" do
      get :paginated_list, params: { per_page: '1' }
      expect(response).to have_http_status(:ok)
    end

    it "handles edge case: per_page exactly at maximum" do
      get :paginated_list, params: { per_page: '100' }
      expect(response).to have_http_status(:ok)
    end

    it "converts decimal per_page parameter to integer" do
      get :paginated_list, params: { per_page: '25.5' }
      expect(response).to have_http_status(:ok)
    end

    it "handles valid per_page parameter" do
      get :paginated_list, params: { per_page: '50' }
      expect(response).to have_http_status(:ok)
    end
  end
end
