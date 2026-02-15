# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncAuthorization, type: :controller, unit: true do
  controller(ApplicationController) do
    include SyncAuthorization

    def index
      render json: { message: "authorized" }
    end

    def show
      @sync_session = SyncSession.find_by(id: params[:id])
      authorize_sync_session_owner!
      render json: { message: "session authorized" } unless performed?
    end

    private

    def root_path
      "/"
    end

    def sync_sessions_path
      "/sync_sessions"
    end
  end

  let(:admin_user) { create(:admin_user, :with_session) }

  before do
    # Skip the Authentication concern's before_action so we can test
    # SyncAuthorization in isolation
    allow(controller).to receive(:authenticate_user!).and_return(true)

    routes.draw do
      get "index" => "anonymous#index"
      get "show/:id" => "anonymous#show"
    end
  end

  describe "#sync_access_allowed?" do
    context "when user is authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "returns true" do
        expect(controller.send(:sync_access_allowed?)).to be true
      end
    end

    context "when user is not authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it "returns false" do
        expect(controller.send(:sync_access_allowed?)).to be false
      end
    end
  end

  describe "#authorize_sync_access!" do
    context "when user is authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "allows access to the action" do
        get :index
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("authorized")
      end
    end

    context "when user is not authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it "redirects to root path with alert for HTML requests" do
        get :index
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq("No tienes permiso para acceder a las sincronizaciones")
      end

      it "returns unauthorized status for JSON requests" do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Unauthorized")
      end

      it "does not render the action body" do
        get :index
        expect(response.body).not_to include("authorized")
      end
    end
  end

  describe "#sync_session_owner?" do
    context "when user is authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "returns true" do
        expect(controller.send(:sync_session_owner?)).to be true
      end
    end

    context "when user is not authenticated" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it "returns false" do
        expect(controller.send(:sync_session_owner?)).to be false
      end
    end
  end

  describe "#authorize_sync_session_owner!" do
    let(:sync_session) { create(:sync_session) }

    context "when user is authenticated (owner check passes)" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "allows access to the action" do
        get :show, params: { id: sync_session.id }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response["message"]).to eq("session authorized")
      end
    end

    context "when user is not authenticated (owner check fails)" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it "redirects with forbidden message for HTML requests" do
        # sync_access_allowed? will also fail for unauthenticated users,
        # so the authorize_sync_access! before_action will block first.
        # We need to skip it to test authorize_sync_session_owner! in isolation.
        allow(controller).to receive(:sync_access_allowed?).and_return(true)

        get :show, params: { id: sync_session.id }
        expect(response).to redirect_to("/sync_sessions")
        expect(flash[:alert]).to eq("No tienes permiso para acceder a esta sincronización")
      end

      it "returns forbidden status for JSON requests" do
        allow(controller).to receive(:sync_access_allowed?).and_return(true)

        get :show, params: { id: sync_session.id }, format: :json
        expect(response).to have_http_status(:forbidden)

        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to eq("Forbidden")
      end
    end
  end

  describe "before_action chain integration" do
    context "when unauthenticated user tries to access index" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
      end

      it "blocks at sync_access_allowed? before reaching the action" do
        get :index
        expect(response).to redirect_to("/")
      end

      it "returns 401 for JSON format" do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated user accesses all actions" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "passes through authorize_sync_access! on index" do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it "passes through both access and owner checks on show" do
        sync_session = create(:sync_session)
        get :show, params: { id: sync_session.id }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "concern inclusion" do
    it "registers authorize_sync_access! as a before_action" do
      before_actions = controller.class._process_action_callbacks
                                .select { |cb| cb.kind == :before }
                                .map(&:filter)
      expect(before_actions).to include(:authorize_sync_access!)
    end
  end
end
