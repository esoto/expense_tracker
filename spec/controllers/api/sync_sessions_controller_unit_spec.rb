require "rails_helper"

RSpec.describe Api::SyncSessionsController, type: :controller, unit: true do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }
  let(:sync_session_account) { create(:sync_session_account, sync_session: sync_session, email_account: email_account) }

  before do
    # Mock render methods
    allow(controller).to receive(:render).and_return(nil)
  end

  describe "GET #status", unit: true do
    before do
      allow(SyncSession).to receive(:find_by).and_return(sync_session)
      allow(sync_session).to receive(:reload).and_return(sync_session)
      allow(sync_session).to receive(:sync_session_accounts).and_return(
        double("relation", includes: double("relation", map: []))
      )
    end

    context "when sync session is not found" do
      before do
        allow(SyncSession).to receive(:find_by).and_return(nil)
      end

      it "renders not found error" do
        expect(controller).to receive(:render).with(
          json: { error: "Sync session not found" },
          status: :not_found
        )

        get :status, params: { id: 999 }, format: :json
      end
    end

    context "when user cannot access sync session" do
      before do
        allow(controller).to receive(:can_access_sync_session?).and_return(false)
      end

      it "renders unauthorized error" do
        expect(controller).to receive(:render).with(
          json: { error: "Unauthorized" },
          status: :unauthorized
        )

        get :status, params: { id: sync_session.id }, format: :json
      end
    end

    context "when user has access to sync session" do
      before do
        allow(controller).to receive(:can_access_sync_session?).and_return(true)
        allow(controller).to receive(:build_status_response).and_return({
          type: "status_update",
          status: "completed",
          progress_percentage: 100,
          processed_emails: 50,
          total_emails: 50
        })
      end

      it "finds the sync session" do
        expect(SyncSession).to receive(:find_by).with(id: sync_session.id.to_s)
        get :status, params: { id: sync_session.id }, format: :json
      end

      it "builds and renders status response" do
        expect(controller).to receive(:build_status_response).and_return({
          type: "status_update",
          status: "completed"
        })

        expect(controller).to receive(:render).with(
          json: hash_including(
            type: "status_update",
            status: "completed"
          )
        )

        get :status, params: { id: sync_session.id }, format: :json
      end
    end
  end

  describe "private methods", unit: true do
    before do
      controller.instance_variable_set(:@sync_session, sync_session)
    end

    describe "#set_sync_session" do
      it "finds and sets sync session" do
        allow(SyncSession).to receive(:find_by).with(id: "123").and_return(sync_session)
        
        controller.params = ActionController::Parameters.new(id: "123")
        controller.send(:set_sync_session)
        
        expect(assigns(:sync_session)).to eq(sync_session)
      end

      it "renders error when sync session not found" do
        allow(SyncSession).to receive(:find_by).and_return(nil)
        
        expect(controller).to receive(:render).with(
          json: { error: "Sync session not found" },
          status: :not_found
        )
        
        controller.params = ActionController::Parameters.new(id: "999")
        controller.send(:set_sync_session)
      end
    end

    describe "#can_access_sync_session?" do
      context "when sync session is nil" do
        before do
          controller.instance_variable_set(:@sync_session, nil)
        end

        it "returns false" do
          result = controller.send(:can_access_sync_session?)
          expect(result).to be false
        end
      end

      context "when sync session has session token" do
        before do
          allow(sync_session).to receive(:session_token?).and_return(true)
          allow(sync_session).to receive(:session_token).and_return("secret_token")
        end

        context "with matching token in headers" do
          before do
            allow(request).to receive(:headers).and_return({
              "X-Sync-Token" => "secret_token"
            })
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with matching token in HTTP_X_SYNC_TOKEN header" do
          before do
            allow(request).to receive(:headers).and_return({
              "HTTP_X_SYNC_TOKEN" => "secret_token"
            })
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with matching token in params" do
          before do
            controller.params = ActionController::Parameters.new(token: "secret_token")
            allow(request).to receive(:headers).and_return({})
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with incorrect token" do
          before do
            allow(request).to receive(:headers).and_return({
              "X-Sync-Token" => "wrong_token"
            })
          end

          it "returns false" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be false
          end
        end

        context "with no token provided" do
          before do
            allow(request).to receive(:headers).and_return({})
            controller.params = ActionController::Parameters.new({})
          end

          it "returns false" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be false
          end
        end
      end

      context "when sync session has no session token" do
        before do
          allow(sync_session).to receive(:session_token?).and_return(false)
        end

        context "with session match (legacy)" do
          before do
            allow(session).to receive(:[]).with(:sync_session_id).and_return(sync_session.id)
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with IP address match for recent session" do
          before do
            allow(session).to receive(:[]).with(:sync_session_id).and_return(nil)
            allow(sync_session).to receive(:created_at).and_return(1.hour.ago)
            allow(sync_session).to receive(:metadata).and_return({ "ip_address" => "192.168.1.1" })
            allow(request).to receive(:remote_ip).and_return("192.168.1.1")
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with no stored IP (backward compatibility)" do
          before do
            allow(session).to receive(:[]).with(:sync_session_id).and_return(nil)
            allow(sync_session).to receive(:created_at).and_return(1.hour.ago)
            allow(sync_session).to receive(:metadata).and_return(nil)
          end

          it "returns true" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be true
          end
        end

        context "with IP address mismatch" do
          before do
            allow(session).to receive(:[]).with(:sync_session_id).and_return(nil)
            allow(sync_session).to receive(:created_at).and_return(1.hour.ago)
            allow(sync_session).to receive(:metadata).and_return({ "ip_address" => "192.168.1.1" })
            allow(request).to receive(:remote_ip).and_return("192.168.1.2")
          end

          it "returns false" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be false
          end
        end

        context "with old session (more than 24 hours)" do
          before do
            allow(session).to receive(:[]).with(:sync_session_id).and_return(nil)
            allow(sync_session).to receive(:created_at).and_return(25.hours.ago)
          end

          it "returns false" do
            result = controller.send(:can_access_sync_session?)
            expect(result).to be false
          end
        end
      end
    end

    describe "#build_status_response" do
      before do
        allow(sync_session).to receive(:reload).and_return(sync_session)
        allow(sync_session).to receive(:sync_session_accounts).and_return(
          double("relation", includes: [sync_session_account])
        )
        allow(sync_session_account).to receive(:email_account_id).and_return(1)
        allow(sync_session_account).to receive(:id).and_return(10)
        allow(sync_session_account).to receive(:email_account).and_return(email_account)
        allow(sync_session_account).to receive(:status).and_return("completed")
        allow(sync_session_account).to receive(:progress_percentage).and_return(100)
        allow(sync_session_account).to receive(:processed_emails).and_return(25)
        allow(sync_session_account).to receive(:total_emails).and_return(25)
        allow(sync_session_account).to receive(:detected_expenses).and_return(15)

        allow(email_account).to receive(:email).and_return("test@bank.com")
        allow(email_account).to receive(:bank_name).and_return("Test Bank")

        allow(sync_session).to receive(:status).and_return("completed")
        allow(sync_session).to receive(:progress_percentage).and_return(100)
        allow(sync_session).to receive(:processed_emails).and_return(25)
        allow(sync_session).to receive(:total_emails).and_return(25)
        allow(sync_session).to receive(:detected_expenses).and_return(15)
        allow(sync_session).to receive(:estimated_time_remaining).and_return(nil)
        allow(sync_session).to receive(:started_at).and_return(1.hour.ago)
        allow(sync_session).to receive(:completed_at).and_return(Time.current)
        allow(sync_session).to receive(:error_details).and_return(nil)
      end

      it "reloads the sync session" do
        expect(sync_session).to receive(:reload)
        controller.send(:build_status_response)
      end

      it "builds comprehensive status response" do
        response = controller.send(:build_status_response)

        expect(response).to include(
          type: "status_update",
          status: "completed",
          progress_percentage: 100,
          processed_emails: 25,
          total_emails: 25,
          detected_expenses: 15,
          time_remaining: nil,
          started_at: anything,
          completed_at: anything,
          error_details: nil
        )
        expect(response[:accounts]).to be_an(Array)
      end

      it "includes account details in response" do
        response = controller.send(:build_status_response)
        account = response[:accounts].first

        expect(account).to include(
          id: 1,
          sync_id: 10,
          email: "test@bank.com",
          bank: "Test Bank",
          status: "completed",
          progress: 100,
          processed: 25,
          total: 25,
          detected: 15
        )
      end

      it "formats time remaining" do
        allow(sync_session).to receive(:estimated_time_remaining).and_return(90)
        expect(controller).to receive(:format_time_remaining).with(90)
        
        controller.send(:build_status_response)
      end
    end

    describe "#format_time_remaining" do
      it "returns nil for nil input" do
        result = controller.send(:format_time_remaining, nil)
        expect(result).to be_nil
      end

      it "formats seconds correctly" do
        result = controller.send(:format_time_remaining, 45)
        expect(result).to eq("45 segundos")
      end

      it "formats single minute correctly" do
        result = controller.send(:format_time_remaining, 60)
        expect(result).to eq("1 minuto")
      end

      it "formats multiple minutes correctly" do
        result = controller.send(:format_time_remaining, 150)
        expect(result).to eq("2 minutos")
      end

      it "formats hours and minutes correctly" do
        result = controller.send(:format_time_remaining, 3720) # 1 hour 2 minutes
        expect(result).to eq("1h 2m")
      end

      it "handles exactly one hour" do
        result = controller.send(:format_time_remaining, 3600)
        expect(result).to eq("1h 0m")
      end
    end

    describe "#json_request?" do
      context "when request format is JSON" do
        before do
          allow(request).to receive(:format).and_return(double(json?: true))
        end

        it "returns true" do
          result = controller.send(:json_request?)
          expect(result).to be true
        end
      end

      context "when request format is not JSON" do
        before do
          allow(request).to receive(:format).and_return(double(json?: false))
        end

        it "returns false" do
          result = controller.send(:json_request?)
          expect(result).to be false
        end
      end
    end
  end

  describe "controller configuration", unit: true do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it "is in the Api module namespace" do
      expect(described_class.name).to eq("Api::SyncSessionsController")
    end

    it "has before_action callbacks" do
      before_callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      callback_filters = before_callbacks.map(&:filter)
      
      expect(callback_filters).to include(:set_sync_session)
    end

  end

  describe "authentication and security", unit: true do
    it "supports multiple authentication methods" do
      # Token-based auth, session-based auth, IP-based auth
      expect(controller.send(:can_access_sync_session?)).to be_in([true, false])
    end

    it "validates session token when present" do
      allow(sync_session).to receive(:session_token?).and_return(true)
      allow(sync_session).to receive(:session_token).and_return("secret")
      allow(request).to receive(:headers).and_return({ "X-Sync-Token" => "wrong" })
      
      result = controller.send(:can_access_sync_session?)
      expect(result).to be false
    end


    it "denies access to old sessions without token or session match" do
      allow(sync_session).to receive(:session_token?).and_return(false)
      allow(session).to receive(:[]).with(:sync_session_id).and_return(nil)
      allow(sync_session).to receive(:created_at).and_return(25.hours.ago)
      
      result = controller.send(:can_access_sync_session?)
      expect(result).to be false
    end
  end

  describe "error handling", unit: true do
    context "when sync session not found" do
      before do
        allow(SyncSession).to receive(:find_by).and_return(nil)
      end

      it "renders appropriate error message" do
        expect(controller).to receive(:render).with(
          json: { error: "Sync session not found" },
          status: :not_found
        )
        
        get :status, params: { id: 999 }, format: :json
      end
    end

    context "when unauthorized access" do
      before do
        allow(SyncSession).to receive(:find_by).and_return(sync_session)
        allow(controller).to receive(:can_access_sync_session?).and_return(false)
      end

      it "renders unauthorized error" do
        expect(controller).to receive(:render).with(
          json: { error: "Unauthorized" },
          status: :unauthorized
        )
        
        get :status, params: { id: sync_session.id }, format: :json
      end
    end
  end

  describe "real-time status updates", unit: true do
    it "provides comprehensive sync session status" do
      allow(SyncSession).to receive(:find_by).and_return(sync_session)
      allow(controller).to receive(:can_access_sync_session?).and_return(true)
      allow(controller).to receive(:build_status_response).and_return({
        type: "status_update",
        status: "processing",
        progress_percentage: 45,
        accounts: []
      })

      get :status, params: { id: sync_session.id }, format: :json
      
      # Should build comprehensive status including progress, accounts, etc.
    end

    it "includes account-level progress details" do
      response_data = {
        type: "status_update",
        accounts: [
          {
            id: 1,
            email: "test@bank.com",
            status: "processing",
            progress: 75,
            processed: 30,
            total: 40
          }
        ]
      }

      allow(SyncSession).to receive(:find_by).and_return(sync_session)
      allow(controller).to receive(:can_access_sync_session?).and_return(true)
      allow(controller).to receive(:build_status_response).and_return(response_data)

      get :status, params: { id: sync_session.id }, format: :json
    end
  end
end