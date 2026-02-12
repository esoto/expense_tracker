# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiCaching, type: :controller, unit: true do
  controller(ApplicationController) do
    include ApiCaching

    def index
      set_cache_headers
      render json: { message: 'success' }
    end

    def show_expense
      expense = Expense.first
      handle_conditional_get(expense)
      render json: expense
    end

    def list_expenses
      expenses = Expense.limit(3)
      handle_conditional_get(expenses)
      render json: expenses
    end

    def disable_cache_endpoint
      disable_cache
      render json: { sensitive: 'data' }
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      post 'index' => 'anonymous#index'
      get 'show_expense' => 'anonymous#show_expense'
      get 'list_expenses' => 'anonymous#list_expenses'
      get 'disable_cache_endpoint' => 'anonymous#disable_cache_endpoint'
    end
  end

  let!(:expense) { create(:expense, amount: 100.0) }
  let!(:expenses) { create_list(:expense, 3) }

  # Use shared examples for standard caching behavior
  it_behaves_like "caching concern"

  describe "#handle_conditional_get", unit: true do
    it "sets ETag for single resources" do
      get :show_expense
      expect(response.headers['ETag']).to be_present
    end

    it "handles collections" do
      get :list_expenses
      expect(response.headers['ETag']).to be_present
    end
  end

  describe "#generate_collection_etag", unit: true do
    it "generates etag for collections with cache_key_with_version" do
      collection = Expense.limit(3)
      etag = controller.send(:generate_collection_etag, collection)
      expect(etag).to be_present
    end

    it "falls back to id-based etag for collections without cache_key" do
      collection = double("collection")
      allow(collection).to receive(:respond_to?).with(:cache_key_with_version).and_return(false)
      allow(collection).to receive(:pluck).with(:id).and_return([ 1, 2, 3 ])
      allow(collection).to receive(:maximum).with(:updated_at).and_return(Time.current)

      etag = controller.send(:generate_collection_etag, collection)
      expect(etag).to include('collection-1-2-3')
    end
  end
end
