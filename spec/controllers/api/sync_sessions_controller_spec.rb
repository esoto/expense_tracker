require 'rails_helper'

RSpec.describe Api::SyncSessionsController, type: :controller do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }
  let(:sync_account) { create(:sync_session_account, sync_session: sync_session, email_account: email_account) }

  describe 'GET #status' do
    context 'with valid sync session' do
      context 'when using token authentication' do
        it 'returns sync session status' do
          sync_account # Create the account
          request.headers['X-Sync-Token'] = sync_session.session_token
          
          get :status, params: { id: sync_session.id }, format: :json
          
          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json['type']).to eq('status_update')
          expect(json['status']).to eq(sync_session.status)
          expect(json['progress_percentage']).to eq(sync_session.progress_percentage)
          expect(json['accounts']).to be_an(Array)
        end
      end

      context 'when using session authentication' do
        it 'returns sync session status' do
          sync_account # Create the account
          session[:sync_session_id] = sync_session.id
          
          get :status, params: { id: sync_session.id }, format: :json
          
          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json['type']).to eq('status_update')
        end
      end

      context 'when using IP-based authentication' do
        let(:sync_session_no_token) { create(:sync_session) }
        
        before do
          # Remove token to test IP-based auth
          sync_session_no_token.update_column(:session_token, nil)
        end
        
        it 'allows access for recent sessions with matching IP' do
          sync_session_no_token.update!(
            created_at: 1.hour.ago,
            metadata: { 'ip_address' => '127.0.0.1' }
          )
          create(:sync_session_account, sync_session: sync_session_no_token, email_account: email_account)
          allow(request).to receive(:remote_ip).and_return('127.0.0.1')
          
          get :status, params: { id: sync_session_no_token.id }, format: :json
          
          expect(response).to have_http_status(:ok)
        end

        it 'denies access for mismatched IP' do
          sync_session_no_token.update!(
            created_at: 1.hour.ago,
            metadata: { 'ip_address' => '192.168.1.1' }
          )
          allow(request).to receive(:remote_ip).and_return('127.0.0.1')
          
          get :status, params: { id: sync_session_no_token.id }, format: :json
          
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'with invalid sync session' do
      it 'returns not found for non-existent session' do
        get :status, params: { id: 'invalid-id' }, format: :json
        
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Sync session not found')
      end

      it 'returns unauthorized without proper authentication' do
        request.headers['X-Sync-Token'] = 'wrong-token'
        
        get :status, params: { id: sync_session.id }, format: :json
        
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with different sync session states' do
      it 'returns completed status correctly' do
        sync_session.update!(
          status: 'completed',
          processed_emails: 50,
          total_emails: 50,
          detected_expenses: 10,
          completed_at: Time.current
        )
        session[:sync_session_id] = sync_session.id
        
        get :status, params: { id: sync_session.id }, format: :json
        
        json = JSON.parse(response.body)
        expect(json['status']).to eq('completed')
        expect(json['progress_percentage']).to eq(100)
        expect(json['processed_emails']).to eq(50)
        expect(json['detected_expenses']).to eq(10)
      end

      it 'returns error details when failed' do
        sync_session.update!(
          status: 'failed',
          error_details: 'Connection timeout'
        )
        session[:sync_session_id] = sync_session.id
        
        get :status, params: { id: sync_session.id }, format: :json
        
        json = JSON.parse(response.body)
        expect(json['status']).to eq('failed')
        expect(json['error_details']).to eq('Connection timeout')
      end
    end
  end
end