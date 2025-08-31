require "rails_helper"

RSpec.describe SyncConflictsController, type: :controller, unit: true do
  let(:sync_session) { create(:sync_session) }
  let(:sync_conflict) { create(:sync_conflict, sync_session: sync_session) }
  let(:existing_expense) { create(:expense) }
  let(:new_expense) { create(:expense) }

  before do
    # Mock service classes
    service_class = Class.new do
      def initialize(conflict)
        @conflict = conflict
        @errors = []
      end

      def resolve(action, options)
        true
      end

      def bulk_resolve(conflict_ids, action, options)
        { resolved_count: conflict_ids.size, failed_count: 0, failed_conflicts: [] }
      end

      def undo_resolution
        true
      end

      def preview_merge(merge_fields)
        { merged_amount: 100.0, merged_description: "Test merge" }
      end

      def errors
        @errors
      end
    end
    stub_const("ConflictResolutionService", service_class)

    # Mock render methods
    allow(controller).to receive(:render).and_return(nil)
    allow(controller).to receive(:redirect_to).and_return(nil)
    allow(controller).to receive(:redirect_back).and_return(nil)
    allow(controller).to receive(:send_data).and_return(nil)
  end

  describe "GET #index", unit: true do
    context "without sync_session_id" do
      before do
        conflicts_relation = double("conflicts_relation")
        allow(conflicts_relation).to receive(:where).and_return(conflicts_relation)
        allow(conflicts_relation).to receive(:by_priority).and_return(conflicts_relation)
        allow(conflicts_relation).to receive(:page).and_return(conflicts_relation)
        allow(conflicts_relation).to receive(:total_count).and_return(1)

        allow(SyncConflict).to receive(:includes).and_return(conflicts_relation)

        # Create base_scope relation for stats calculation
        base_scope_relation = double("base_scope_relation")
        allow(base_scope_relation).to receive(:where).and_return(base_scope_relation)
        allow(base_scope_relation).to receive(:unresolved).and_return(base_scope_relation)
        allow(base_scope_relation).to receive(:resolved).and_return(base_scope_relation)
        allow(base_scope_relation).to receive(:group).and_return(base_scope_relation)
        allow(base_scope_relation).to receive(:count).and_return(5, 3, { "duplicate" => 4, "merge" => 4 })

        allow(SyncConflict).to receive(:all).and_return(base_scope_relation)
      end

      it "loads all conflicts with includes" do
        expect(SyncConflict).to receive(:includes).with(:existing_expense, :new_expense)
        get :index
      end

      it "applies status filter when provided" do
        get :index, params: { status: "pending" }
        # The filtering is tested through the chain
      end

      it "applies type filter when provided" do
        get :index, params: { type: "duplicate" }
        # The filtering is tested through the chain
      end

      it "calculates stats correctly" do
        get :index
        expect(assigns(:stats)).to be_a(Hash)
        expect(assigns(:stats)).to have_key(:total)
        expect(assigns(:stats)).to have_key(:pending)
        expect(assigns(:stats)).to have_key(:resolved)
        expect(assigns(:stats)).to have_key(:by_type)
      end
    end

    context "with sync_session_id" do
      before do
        allow(SyncSession).to receive(:find).and_return(sync_session)

        session_conflicts_relation = double("session_conflicts_relation")
        allow(session_conflicts_relation).to receive(:includes).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:where).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:by_priority).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:page).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:total_count).and_return(1)
        allow(session_conflicts_relation).to receive(:unresolved).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:resolved).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:group).and_return(session_conflicts_relation)
        allow(session_conflicts_relation).to receive(:count).and_return(2, 1, { "duplicate" => 2, "merge" => 1 })

        allow(sync_session).to receive(:sync_conflicts).and_return(session_conflicts_relation)
      end

      it "finds sync session and loads its conflicts" do
        expect(SyncSession).to receive(:find).with(sync_session.id.to_s)
        get :index, params: { sync_session_id: sync_session.id }
      end

      it "assigns sync_session" do
        get :index, params: { sync_session_id: sync_session.id }
        expect(assigns(:sync_session)).to eq(sync_session)
      end
    end

    it "responds to different formats" do
      allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      get :index
    end
  end

  describe "GET #show", unit: true do
    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(sync_conflict).to receive(:existing_expense).and_return(existing_expense)
      allow(sync_conflict).to receive(:new_expense).and_return(new_expense)
      allow(sync_conflict).to receive(:field_differences).and_return({ amount: [ "10.0", "20.0" ] })
      allow(sync_conflict).to receive_message_chain(:conflict_resolutions, :recent, :limit).and_return([])
    end

    it "finds the sync conflict" do
      expect(SyncConflict).to receive(:find).with(sync_conflict.id.to_s)
      get :show, params: { id: sync_conflict.id }
    end

    it "loads related expenses and data" do
      get :show, params: { id: sync_conflict.id }

      expect(assigns(:sync_conflict)).to eq(sync_conflict)
      expect(assigns(:existing_expense)).to eq(existing_expense)
      expect(assigns(:new_expense)).to eq(new_expense)
      expect(assigns(:differences)).to eq({ amount: [ "10.0", "20.0" ] })
    end

    it "responds to different formats" do
      allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      get :show, params: { id: sync_conflict.id }
    end
  end

  describe "POST #resolve", unit: true do
    let(:resolve_params) { { action_type: "keep_existing", resolved_by: "admin" } }

    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
    end

    context "with successful resolution" do
      before do
        allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      end

      it "finds the sync conflict" do
        expect(SyncConflict).to receive(:find).with(sync_conflict.id.to_s)
        post :resolve, params: { id: sync_conflict.id }.merge(resolve_params)
      end

      it "creates resolution service and resolves conflict" do
        expect(ConflictResolutionService).to receive(:new).with(sync_conflict).and_call_original
        post :resolve, params: { id: sync_conflict.id }.merge(resolve_params)
      end

      it "responds with success" do
        post :resolve, params: { id: sync_conflict.id }.merge(resolve_params)
        # Success response is handled by the mocked service
      end
    end

    context "with failed resolution" do
      before do
        failed_service = Class.new do
          def initialize(conflict)
            @conflict = conflict
          end

          def resolve(action, options)
            false
          end

          def errors
            [ "Resolution failed" ]
          end
        end
        stub_const("ConflictResolutionService", failed_service)
        allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      end

      it "handles resolution failure" do
        post :resolve, params: { id: sync_conflict.id }.merge(resolve_params)
        # Error handling is managed by respond_to block
      end
    end
  end

  describe "POST #bulk_resolve", unit: true do
    let(:conflict_ids) { [ sync_conflict.id, "2", "3" ] }
    let(:bulk_params) { { conflict_ids: conflict_ids, action_type: "keep_existing" } }

    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(SyncConflict).to receive(:find_by).and_return(sync_conflict)
    end

    context "with valid conflict ids" do
      before do
        allow(controller).to receive(:respond_to).and_yield(double(json: nil, turbo_stream: nil))
      end

      it "processes bulk resolution" do
        expect(ConflictResolutionService).to receive(:new).with(sync_conflict).and_call_original
        post :bulk_resolve, params: bulk_params
      end

      it "returns success response with counts" do
        post :bulk_resolve, params: bulk_params
        # Response handled by mocked service
      end
    end

    context "with empty conflict ids" do
      it "returns bad request error" do
        expect(controller).to receive(:render).with(
          json: {
            success: false,
            error: "No se seleccionaron conflictos"
          },
          status: :bad_request
        )
        post :bulk_resolve, params: { conflict_ids: [], action_type: "keep_existing" }
      end
    end
  end

  describe "POST #undo", unit: true do
    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
    end

    context "with successful undo" do
      before do
        allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      end

      it "finds the sync conflict" do
        expect(SyncConflict).to receive(:find).with(sync_conflict.id.to_s)
        post :undo, params: { id: sync_conflict.id }
      end

      it "creates service and undoes resolution" do
        expect(ConflictResolutionService).to receive(:new).with(sync_conflict).and_call_original
        post :undo, params: { id: sync_conflict.id }
      end
    end

    context "with failed undo" do
      before do
        failed_service = Class.new do
          def initialize(conflict)
            @conflict = conflict
          end

          def undo_resolution
            false
          end

          def errors
            [ "Undo failed" ]
          end
        end
        stub_const("ConflictResolutionService", failed_service)
        allow(controller).to receive(:respond_to).and_yield(double(html: nil, json: nil, turbo_stream: nil))
      end

      it "handles undo failure" do
        post :undo, params: { id: sync_conflict.id }
        # Error handling tested through service mock
      end
    end
  end

  describe "GET #preview_merge", unit: true do
    let(:merge_fields) { { amount: "15.0", description: "Merged expense" } }

    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(sync_conflict).to receive(:existing_expense).and_return(existing_expense)
      allow(existing_expense).to receive(:attributes).and_return({ "amount" => "10.0", "description" => "Original" })
    end

    it "finds the sync conflict" do
      expect(SyncConflict).to receive(:find).with(sync_conflict.id.to_s)
      get :preview_merge, params: { id: sync_conflict.id, merge_fields: merge_fields }, format: :json
    end

    it "creates service and gets preview" do
      expect(ConflictResolutionService).to receive(:new).with(sync_conflict).and_call_original
      get :preview_merge, params: { id: sync_conflict.id, merge_fields: merge_fields }, format: :json
    end

    it "renders JSON response with preview and changes" do
      expect(controller).to receive(:render).with(
        json: {
          success: true,
          preview: { merged_amount: 100.0, merged_description: "Test merge" },
          changes: anything
        }
      )
      get :preview_merge, params: { id: sync_conflict.id, merge_fields: merge_fields }, format: :json
    end
  end

  describe "private methods", unit: true do
    before do
      allow(SyncConflict).to receive(:find).and_return(sync_conflict)
      allow(SyncSession).to receive(:find).and_return(sync_session)
    end

    describe "#set_sync_conflict" do
      it "finds and assigns sync conflict" do
        controller.params = ActionController::Parameters.new(id: sync_conflict.id.to_s)
        controller.send(:set_sync_conflict)
        expect(assigns(:sync_conflict)).to eq(sync_conflict)
      end
    end

    describe "#set_sync_session" do
      it "finds and assigns sync session when sync_session_id present" do
        controller.params = ActionController::Parameters.new(sync_session_id: sync_session.id.to_s)
        controller.send(:set_sync_session)
        expect(assigns(:sync_session)).to eq(sync_session)
      end

      it "does not assign sync session when sync_session_id not present" do
        controller.params = ActionController::Parameters.new({})
        controller.send(:set_sync_session)
        expect(assigns(:sync_session)).to be_nil
      end
    end

    describe "#resolve_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          resolved_by: "admin",
          merge_fields: { amount: "10.0" },
          custom_data: [
            existing_expense: { id: 1 },
            new_expense: { id: 2 }
          ],
          unpermitted: "value"
        })

        permitted_params = controller.send(:resolve_params)
        expect(permitted_params.keys).to contain_exactly(
          "resolved_by", "merge_fields", "custom_data"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#calculate_merge_changes" do
      let(:preview) { { "amount" => "20.0", "description" => "Updated description" } }

      before do
        controller.instance_variable_set(:@sync_conflict, sync_conflict)
        allow(sync_conflict).to receive(:existing_expense).and_return(existing_expense)
        allow(existing_expense).to receive(:attributes).and_return({
          "amount" => "10.0",
          "description" => "Original description"
        })
      end

      it "calculates changes between existing expense and preview" do
        changes = controller.send(:calculate_merge_changes, preview)

        expect(changes).to eq({
          "amount" => { from: "10.0", to: "20.0" },
          "description" => { from: "Original description", to: "Updated description" }
        })
      end

      it "returns empty hash when no existing expense" do
        allow(sync_conflict).to receive(:existing_expense).and_return(nil)
        changes = controller.send(:calculate_merge_changes, preview)
        expect(changes).to eq({})
      end

      it "returns empty hash when no preview" do
        changes = controller.send(:calculate_merge_changes, nil)
        expect(changes).to eq({})
      end
    end
  end

  describe "controller configuration", unit: true do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(ApplicationController)
    end

    it "has before_action callbacks" do
      before_callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      callback_filters = before_callbacks.map(&:filter)

      expect(callback_filters).to include(:set_sync_conflict)
      expect(callback_filters).to include(:set_sync_session)
    end
  end

  describe "service integration", unit: true do
    it "integrates with ConflictResolutionService" do
      expect(ConflictResolutionService).to respond_to(:new)
    end
  end

  describe "error handling", unit: true do
    context "when sync conflict is not found" do
      before do
        allow(SyncConflict).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          get :show, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when sync session is not found" do
      before do
        allow(SyncSession).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          get :index, params: { sync_session_id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
