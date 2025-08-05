require 'rails_helper'

RSpec.describe SyncAuthorization, type: :controller do
  controller(ApplicationController) do
    include SyncAuthorization

    def index
      render plain: "authorized"
    end
  end

  describe '#authorize_sync_access!' do
    context 'when sync access is allowed' do
      before do
        allow(controller).to receive(:sync_access_allowed?).and_return(true)
      end

      it 'allows access to the action' do
        get :index
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("authorized")
      end
    end

    context 'when sync access is denied' do
      before do
        allow(controller).to receive(:sync_access_allowed?).and_return(false)
      end

      it 'redirects to root path with alert for HTML requests' do
        get :index
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("No tienes permiso para acceder a las sincronizaciones")
      end

      it 'returns unauthorized status for JSON requests' do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("Unauthorized")
      end
    end
  end

  describe '#sync_access_allowed?' do
    it 'returns true by default (placeholder)' do
      # This is a placeholder implementation
      expect(controller.send(:sync_access_allowed?)).to be true
    end
  end

  describe '#authorize_sync_session_owner!' do
    controller(ApplicationController) do
      include SyncAuthorization

      def show
        authorize_sync_session_owner!
        render plain: "authorized" unless performed?
      end
    end

    context 'when user owns the sync session' do
      before do
        allow(controller).to receive(:sync_session_owner?).and_return(true)
      end

      it 'allows access' do
        get :show, params: { id: 1 }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user does not own the sync session' do
      before do
        allow(controller).to receive(:sync_session_owner?).and_return(false)
        allow(controller).to receive(:sync_sessions_path).and_return('/sync_sessions')
      end

      it 'redirects with forbidden message for HTML' do
        get :show, params: { id: 1 }
        expect(response).to redirect_to('/sync_sessions')
        expect(flash[:alert]).to eq("No tienes permiso para acceder a esta sincronización")
      end

      it 'returns forbidden status for JSON' do
        get :show, params: { id: 1 }, format: :json
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["error"]).to eq("Forbidden")
      end
    end
  end
end
