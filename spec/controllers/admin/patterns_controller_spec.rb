# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::PatternsController, type: :controller do
  let(:admin_user) { create(:admin_user, role: :admin) }
  let(:category) { Category.create!(name: 'Test Category') }
  let(:valid_attributes) do
    {
      pattern_type: 'merchant',
      pattern_value: 'Starbucks',
      category_id: category.id,
      confidence_weight: 1.5,
      active: true
    }
  end

  let(:invalid_attributes) do
    {
      pattern_type: nil,
      pattern_value: '',
      category_id: nil
    }
  end

  before do
    # Mock admin authentication
    allow(controller).to receive(:admin_signed_in?).and_return(true)
    allow(controller).to receive(:current_admin_user).and_return(admin_user)
    allow(controller).to receive(:require_admin_authentication).and_return(true)
    allow(controller).to receive(:check_session_expiry).and_return(true)
    allow(controller).to receive(:set_security_headers).and_return(true)
    allow(controller).to receive(:check_rate_limit).and_return(true)
    allow(controller).to receive(:log_admin_activity).and_return(true)

    # Mock permission checks
    allow(controller).to receive(:require_pattern_management_permission).and_return(true)
    allow(controller).to receive(:require_pattern_edit_permission).and_return(true)
    allow(controller).to receive(:require_pattern_delete_permission).and_return(true)
    allow(controller).to receive(:require_import_permission).and_return(true)
    allow(controller).to receive(:require_statistics_permission).and_return(true)
    allow(controller).to receive(:check_rate_limit_for_testing).and_return(true)
    allow(controller).to receive(:check_rate_limit_for_import).and_return(true)
  end

  describe "GET #index" do
    it "returns a success response" do
      CategorizationPattern.create!(valid_attributes)
      get :index
      expect(response).to be_successful
    end

    it "loads patterns with statistics", :skip do
      pattern = CategorizationPattern.create!(valid_attributes)
      get :index
      expect(assigns(:patterns)).to include(pattern)
      expect(assigns(:total_patterns)).to be_present
      expect(assigns(:active_patterns)).to be_present
    end
  end

  describe "GET #show" do
    it "returns a success response" do
      pattern = CategorizationPattern.create!(valid_attributes)
      get :show, params: { id: pattern.to_param }
      expect(response).to be_successful
    end
  end

  describe "GET #new" do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      pattern = CategorizationPattern.create!(valid_attributes)
      get :edit, params: { id: pattern.to_param }
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new CategorizationPattern" do
        expect {
          post :create, params: { categorization_pattern: valid_attributes }
        }.to change(CategorizationPattern, :count).by(1)
      end

      it "redirects to the created pattern" do
        post :create, params: { categorization_pattern: valid_attributes }
        expect(response).to redirect_to(admin_pattern_path(CategorizationPattern.last))
      end

      it "marks pattern as user_created" do
        post :create, params: { categorization_pattern: valid_attributes }
        expect(CategorizationPattern.last.user_created).to be true
      end
    end

    context "with invalid params" do
      it "returns unprocessable entity status" do
        post :create, params: { categorization_pattern: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PUT #update" do
    context "with valid params" do
      let(:new_attributes) do
        {
          pattern_value: 'updated value',
          confidence_weight: 2.5
        }
      end

      it "updates the requested pattern" do
        pattern = CategorizationPattern.create!(valid_attributes)
        put :update, params: { id: pattern.to_param, categorization_pattern: new_attributes }
        pattern.reload
        expect(pattern.pattern_value).to eq('updated value')
        expect(pattern.confidence_weight).to eq(2.5)
      end

      it "redirects to the pattern" do
        pattern = CategorizationPattern.create!(valid_attributes)
        put :update, params: { id: pattern.to_param, categorization_pattern: new_attributes }
        expect(response).to redirect_to(admin_pattern_path(pattern))
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys the requested pattern" do
      pattern = CategorizationPattern.create!(valid_attributes)
      expect {
        delete :destroy, params: { id: pattern.to_param }
      }.to change(CategorizationPattern, :count).by(-1)
    end

    it "redirects to the patterns list" do
      pattern = CategorizationPattern.create!(valid_attributes)
      delete :destroy, params: { id: pattern.to_param }
      expect(response).to redirect_to(admin_patterns_path)
    end
  end

  # toggle_active action moved to Admin::PatternManagementController

  # Test, import, export, statistics, and performance actions moved to dedicated controllers:
  # - Testing actions moved to Admin::PatternTestingController
  # - Management actions moved to Admin::PatternManagementController
end
