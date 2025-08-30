require "rails_helper"

RSpec.describe SyncSessionsController, type: :controller, unit: true do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }

  before do
    # Mock service classes to avoid actual implementation calls
    allow(SyncSessionCreator).to receive(:new).and_return(double(call: double(success?: true, sync_session: sync_session)))
    allow(SyncSessionRetryService).to receive(:new).and_return(double(call: double(success?: true, sync_session: sync_session)))
    allow(SyncSessionPerformanceOptimizer).to receive(:preload_for_index).and_return([sync_session])
    allow(SyncSessionPerformanceOptimizer).to receive(:preload_for_show).and_return([])
    allow(SyncSessionPerformanceOptimizer).to receive(:cache_key_for_status).and_return("sync_status_#{sync_session.id}")
    allow(SyncSessionPerformanceOptimizer).to receive(:calculate_metrics).and_return({})
    
    # Mock render and redirect methods to avoid template issues
    allow(controller).to receive(:render).and_return(nil)
    allow(controller).to receive(:redirect_to).and_return(nil)
  end

  describe "GET #index", unit: true do
    let(:active_session) { sync_session }
    let(:recent_sessions) { [sync_session] }

    before do
      allow(SyncSession).to receive_message_chain(:active, :includes).and_return(double(first: active_session))
      preload_chain = double("preload_chain")
      allow(SyncSessionPerformanceOptimizer).to receive(:preload_for_index).and_return(preload_chain)
      allow(preload_chain).to receive(:limit).with(10).and_return(recent_sessions)
      allow(EmailAccount).to receive_message_chain(:active, :order).and_return([email_account])
      allow(EmailAccount).to receive_message_chain(:active, :count).and_return(1)
      allow(SyncSession).to receive(:where).and_return(double(count: 5))
      allow(SyncSession).to receive_message_chain(:completed, :where, :sum).and_return(50)
      allow(SyncSession).to receive_message_chain(:completed, :recent, :first).and_return(sync_session)
    end

    it "loads active session" do
      get :index
      expect(assigns(:active_session)).to eq(active_session)
    end

    it "loads recent sessions" do
      get :index
      expect(assigns(:recent_sessions)).to eq(recent_sessions)
    end

    it "loads email accounts" do
      get :index
      expect(assigns(:email_accounts)).to eq([email_account])
    end

    it "calculates dashboard statistics" do
      get :index
      expect(assigns(:active_accounts_count)).to eq(1)
      expect(assigns(:today_sync_count)).to eq(5)
      expect(assigns(:monthly_expenses_detected)).to eq(50)
      expect(assigns(:last_completed_session)).to eq(sync_session)
    end
  end

  describe "GET #show", unit: true do
    before do
      allow(SyncSession).to receive(:find).and_return(sync_session)
      allow(controller).to receive(:authorize_sync_session_owner!)
    end

    it "finds and assigns sync session" do
      expect(SyncSession).to receive(:find).with(sync_session.id.to_s)
      get :show, params: { id: sync_session.id }
      expect(assigns(:sync_session)).to eq(sync_session)
    end

    it "loads session accounts data" do
      get :show, params: { id: sync_session.id }
      expect(assigns(:session_accounts)).to eq([])
    end
  end

  describe "POST #create", unit: true do
    let(:sync_creator) { double("sync_creator") }
    let(:creation_result) { double("result", success?: true, sync_session: sync_session) }

    before do
      allow(SyncSessionCreator).to receive(:new).and_return(sync_creator)
      allow(sync_creator).to receive(:call).and_return(creation_result)
      allow(controller).to receive(:prepare_widget_data)
      allow(controller).to receive(:respond_to).and_yield(double(turbo_stream: nil, html: nil, json: nil))
    end

    context "with valid parameters" do
      let(:valid_params) { { email_account_id: email_account.id, since: "2023-01-01" } }

      it "creates sync session with proper service" do
        expect(SyncSessionCreator).to receive(:new).with(
          hash_including("email_account_id" => email_account.id.to_s, "since" => "2023-01-01"),
          hash_including(:ip_address, :user_agent, :session_id, :source)
        )
        
        post :create, params: valid_params
      end

      it "stores sync session ID in Rails session" do
        post :create, params: valid_params
        expect(session[:sync_session_id]).to eq(sync_session.id)
      end

      it "assigns sync session instance variable" do
        post :create, params: valid_params
        expect(assigns(:sync_session)).to eq(sync_session)
      end

      it "handles turbo stream format responses" do
        post :create, params: valid_params, format: :turbo_stream
        expect(assigns(:sync_session)).to eq(sync_session)
      end
    end

    context "with invalid parameters" do
      let(:creation_result) { double("result", success?: false, message: "Error message", error: :validation_error) }

      before do
        allow(sync_creator).to receive(:call).and_return(creation_result)
        allow(controller).to receive(:handle_creation_error)
      end

      it "handles creation error" do
        expect(controller).to receive(:handle_creation_error).with(creation_result)
        post :create, params: { email_account_id: nil }
      end
    end
  end

  describe "POST #cancel", unit: true do
    before do
      allow(SyncSession).to receive(:find).and_return(sync_session)
      allow(controller).to receive(:authorize_sync_session_owner!)
      allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil))
    end

    context "when sync session is active" do
      before do
        allow(sync_session).to receive(:active?).and_return(true)
        allow(sync_session).to receive(:cancel!)
      end

      it "cancels the sync session" do
        expect(sync_session).to receive(:cancel!)
        post :cancel, params: { id: sync_session.id }
      end
    end

    context "when sync session is not active" do
      before do
        allow(sync_session).to receive(:active?).and_return(false)
      end

      it "redirects with alert" do
        expect(controller).to receive(:redirect_to).with(sync_sessions_path, alert: "Esta sincronización no está activa")
        post :cancel, params: { id: sync_session.id }
      end
    end

    context "when error occurs" do
      before do
        allow(sync_session).to receive(:active?).and_return(true)
        allow(sync_session).to receive(:cancel!).and_raise(StandardError, "Test error")
      end

      it "handles error and redirects" do
        expect(Rails.logger).to receive(:error).with(/Error cancelling sync session/)
        expect(controller).to receive(:redirect_to).with(sync_sessions_path, alert: "Error al cancelar la sincronización")
        post :cancel, params: { id: sync_session.id }
      end
    end
  end

  describe "POST #retry", unit: true do
    let(:retry_service) { double("retry_service") }
    let(:retry_result) { double("result", success?: true, sync_session: sync_session) }

    before do
      allow(SyncSession).to receive(:find).and_return(sync_session)
      allow(controller).to receive(:authorize_sync_session_owner!)
      allow(SyncSessionRetryService).to receive(:new).and_return(retry_service)
      allow(retry_service).to receive(:call).and_return(retry_result)
      allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil))
    end

    context "with successful retry" do
      let(:retry_params) { { since: "2023-01-01" } }

      it "creates retry service with correct parameters" do
        expect(SyncSessionRetryService).to receive(:new).with(sync_session, hash_including("since" => "2023-01-01"))
        post :retry, params: { id: sync_session.id, **retry_params }
      end

      it "calls retry service" do
        expect(retry_service).to receive(:call)
        post :retry, params: { id: sync_session.id }
      end
    end

    context "with failed retry" do
      let(:retry_result) { double("result", success?: false, error: :rate_limit_exceeded, message: "Rate limit") }

      before do
        allow(retry_service).to receive(:call).and_return(retry_result)
        allow(controller).to receive(:handle_retry_error)
      end

      it "handles retry error" do
        expect(controller).to receive(:handle_retry_error).with(retry_result)
        post :retry, params: { id: sync_session.id }
      end
    end
  end

  describe "GET #status", unit: true do
    let(:session_id) { sync_session.id }

    before do
      allow(Rails.cache).to receive(:fetch).and_return({ status: "running" })
    end

    context "when session exists" do
      before do
        allow(SyncSession).to receive(:find_by).with(id: session_id.to_s).and_return(sync_session)
        allow(controller).to receive(:build_status_response).and_return({ status: "running" })
        allow(controller).to receive(:render).with(json: { status: "running" })
      end

      it "finds session by ID" do
        expect(SyncSession).to receive(:find_by).with(id: session_id.to_s)
        get :status, params: { sync_session_id: session_id }, format: :json
      end

      it "uses caching for status data" do
        expect(Rails.cache).to receive(:fetch).with(
          "sync_status_#{sync_session.id}",
          hash_including(expires_in: 5.seconds, race_condition_ttl: 2.seconds)
        )
        get :status, params: { sync_session_id: session_id }, format: :json
      end

      it "renders status data as JSON" do
        expect(controller).to receive(:render).with(json: { status: "running" })
        get :status, params: { sync_session_id: session_id }, format: :json
      end
    end

    context "when session does not exist" do
      before do
        allow(SyncSession).to receive(:find_by).with(id: "999").and_return(nil)
        allow(controller).to receive(:render).with(json: { error: "Session not found" }, status: :not_found)
      end

      it "renders not found error" do
        expect(controller).to receive(:render).with(json: { error: "Session not found" }, status: :not_found)
        get :status, params: { sync_session_id: "999" }, format: :json
      end
    end
  end

  describe "private methods", unit: true do
    describe "#set_sync_session" do
      it "finds sync session by ID" do
        expect(SyncSession).to receive(:find).with("123").and_return(sync_session)
        
        controller.params = ActionController::Parameters.new(id: "123")
        controller.send(:set_sync_session)
        
        expect(controller.instance_variable_get(:@sync_session)).to eq(sync_session)
      end
    end

    describe "#prepare_widget_data" do
      before do
        controller.instance_variable_set(:@sync_session, sync_session)
        allow(SyncSession).to receive_message_chain(:completed, :recent, :first).and_return(sync_session)
      end

      it "sets active sync session" do
        controller.send(:prepare_widget_data)
        expect(controller.instance_variable_get(:@active_sync_session)).to eq(sync_session)
      end

      it "loads last completed sync" do
        controller.send(:prepare_widget_data)
        expect(controller.instance_variable_get(:@last_completed_sync)).to eq(sync_session)
      end
    end

    describe "#sync_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          email_account_id: "1",
          since: "2023-01-01",
          unpermitted: "value"
        })

        permitted_params = controller.send(:sync_params)

        expect(permitted_params.keys).to contain_exactly("email_account_id", "since")
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#retry_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          since: "2023-01-01",
          unpermitted: "value"
        })

        permitted_params = controller.send(:retry_params)

        expect(permitted_params.keys).to contain_exactly("since")
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#request_info" do
      before do
        allow(controller.request).to receive(:remote_ip).and_return("127.0.0.1")
        allow(controller.request).to receive(:user_agent).and_return("Test Agent")
        allow(controller.session).to receive(:id).and_return(double(to_s: "session123"))
      end

      it "returns request information hash" do
        result = controller.send(:request_info)
        
        expect(result).to include(
          ip_address: "127.0.0.1",
          user_agent: "Test Agent",
          session_id: "session123",
          source: "web"
        )
      end
    end

    describe "#build_status_response" do
      let(:session_account) { double("session_account", email_account: email_account) }

      before do
        allow(sync_session).to receive_message_chain(:sync_session_accounts, :includes).and_return([session_account])
        allow(sync_session).to receive(:status).and_return("running")
        allow(sync_session).to receive(:progress_percentage).and_return(50)
        allow(sync_session).to receive(:processed_emails).and_return(100)
        allow(sync_session).to receive(:total_emails).and_return(200)
        allow(sync_session).to receive(:detected_expenses).and_return(25)
        allow(sync_session).to receive(:estimated_time_remaining).and_return(300)
        
        allow(session_account).to receive(:id).and_return(1)
        allow(session_account).to receive(:status).and_return("running")
        allow(session_account).to receive(:progress_percentage).and_return(45)
        allow(session_account).to receive(:processed_emails).and_return(50)
        allow(session_account).to receive(:total_emails).and_return(100)
        allow(session_account).to receive(:detected_expenses).and_return(10)
        
        allow(email_account).to receive(:email).and_return("test@bank.com")
        allow(email_account).to receive(:bank_name).and_return("Test Bank")
      end

      it "builds complete status response" do
        result = controller.send(:build_status_response, sync_session)
        
        expect(result).to include(
          status: "running",
          progress_percentage: 50,
          processed_emails: 100,
          total_emails: 200,
          detected_expenses: 25,
          time_remaining: 300,
          metrics: {},
          accounts: [
            {
              id: 1,
              email: "test@bank.com",
              bank: "Test Bank",
              status: "running",
              progress: 45,
              processed: 50,
              total: 100,
              detected: 10
            }
          ]
        )
      end
    end

    describe "#handle_creation_error" do
      let(:result) { double("result", message: "Error message", error: :validation_error) }

      before do
        allow(controller).to receive(:respond_to).and_yield(double(turbo_stream: nil, html: nil, json: nil))
      end

      it "handles creation errors properly" do
        expect(controller).to receive(:respond_to)
        controller.send(:handle_creation_error, result)
      end
    end

    describe "#handle_retry_error" do
      let(:result) { double("result", message: "Retry error", error: :rate_limit_exceeded) }

      before do
        allow(controller).to receive(:handle_rate_limit_exceeded)
      end

      context "with rate limit error" do
        it "handles rate limit exceeded" do
          expect(controller).to receive(:handle_rate_limit_exceeded)
          controller.send(:handle_retry_error, result)
        end
      end

      context "with other error" do
        let(:result) { double("result", message: "Other error", error: :other_error) }

        it "redirects with error message" do
          expect(controller).to receive(:redirect_to).with(sync_sessions_path, alert: "Other error")
          controller.send(:handle_retry_error, result)
        end
      end
    end
  end

  describe "authorization and callbacks", unit: true do
    it "sets sync session before show, cancel, and retry actions" do
      callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      set_session_callback = callbacks.find { |cb| cb.filter == :set_sync_session }
      
      expect(set_session_callback).to be_present
    end

    it "authorizes sync session owner before show, cancel, and retry actions" do
      callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      authorize_callback = callbacks.find { |cb| cb.filter == :authorize_sync_session_owner! }
      
      expect(authorize_callback).to be_present
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it "includes SyncAuthorization concern" do
      expect(described_class.included_modules.map(&:name)).to include("SyncAuthorization")
    end

    it "includes SyncErrorHandling concern" do
      expect(described_class.included_modules.map(&:name)).to include("SyncErrorHandling")
    end
  end
end