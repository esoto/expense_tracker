# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncAuthorization, type: :controller, unit: true do
  controller(ApplicationController) do
    include SyncAuthorization

    def index
      render json: { message: 'authorized' }
    end

    def show
      authorize_sync_session_owner!
      render json: { message: 'session authorized' } unless performed?
    end

    private

    def root_path
      '/'
    end

    def sync_sessions_path
      '/sync_sessions'
    end
  end

  before do
    routes.draw do
      get 'index' => 'anonymous#index'
      get 'show/:id' => 'anonymous#show'
    end
  end

  # Note: Cannot use authorization concern shared examples as
  # methods are private and not accessible

  describe "sync access authorization", unit: true do
    context "when sync access is allowed" do
      before do
        allow(controller).to receive(:sync_access_allowed?).and_return(true)
      end

      it "allows access to the action" do
        get :index
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('authorized')
      end
    end

    context "when sync access is denied" do
      before do
        allow(controller).to receive(:sync_access_allowed?).and_return(false)
      end

      it "redirects to root path with alert for HTML requests" do
        get :index
        expect(response).to redirect_to('/')
        expect(flash[:alert]).to eq("No tienes permiso para acceder a las sincronizaciones")
      end

      it "returns unauthorized status for JSON requests" do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq("Unauthorized")
      end
    end
  end

  describe "sync access check", unit: true do
    it "returns true by default (placeholder implementation)" do
      expect(controller.send(:sync_access_allowed?)).to be true
    end
  end

  describe "session owner authorization", unit: true do
    context "when user owns the sync session" do
      before do
        allow(controller).to receive(:sync_session_owner?).and_return(true)
      end

      it "allows access" do
        get :show, params: { id: 1 }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('session authorized')
      end
    end

    context "when user does not own the sync session" do
      before do
        allow(controller).to receive(:sync_session_owner?).and_return(false)
      end

      it "redirects with forbidden message for HTML" do
        get :show, params: { id: 1 }
        expect(response).to redirect_to('/sync_sessions')
        expect(flash[:alert]).to eq("No tienes permiso para acceder a esta sincronización")
      end

      it "returns forbidden status for JSON" do
        get :show, params: { id: 1 }, format: :json
        expect(response).to have_http_status(:forbidden)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq("Forbidden")
      end
    end
  end

  describe "session ownership check", unit: true do
    it "returns true by default (placeholder implementation)" do
      expect(controller.send(:sync_session_owner?)).to be true
    end
  end
end
