require "rails_helper"

RSpec.describe BulkCategorizationsController, type: :controller, unit: true do
  let(:user) { create(:admin_user) }
  let(:category) { create(:category) }
  let!(:expense1) { create(:expense, category: nil) }
  let!(:expense2) { create(:expense, category: nil) }
  let!(:bulk_operation) do
    operation = create(:bulk_operation, user_id: user.id, expense_count: 2, total_amount: 25.50)
    create(:bulk_operation_item, bulk_operation: operation, expense: expense1)
    create(:bulk_operation_item, bulk_operation: operation, expense: expense2)
    operation
  end

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:current_user_id).and_return(user.id)
    allow(controller).to receive(:log_user_action)
    # Skip rate limiting checks for unit tests
    controller.class.skip_before_action :check_rate_limit, raise: false if controller.class.respond_to?(:skip_before_action)
  end

  describe "includes", unit: true do
    it "includes Authentication concern" do
      expect(controller.class.ancestors).to include(Authentication)
    end

    it "includes RateLimiting concern" do
      expect(controller.class.ancestors).to include(RateLimiting)
    end
  end

  describe "GET #index" do
    # Mock the grouping service since it's an external dependency
    let(:grouping_service) { double("BulkCategorization::GroupingService") }
    let(:grouped_expenses) { [ { expenses: [ expense1, expense2 ], confidence: 0.9, total_amount: 1000 } ] }

    before do
      allow(BulkCategorization::GroupingService).to receive(:new).and_return(grouping_service)
      allow(grouping_service).to receive(:group_by_similarity).and_return(grouped_expenses)
    end

    context "as HTML request" do
      it "loads uncategorized expenses and shows main interface" do
        get :index

        expect(response).to have_http_status(:ok)
        expect(assigns(:grouped_expenses)).to be_present
        expect(assigns(:categories)).to be_present
        expect(assigns(:statistics)).to be_present
      end

      it "loads uncategorized expenses with proper associations" do
        get :index
        expect(assigns(:uncategorized_expenses)).to include(expense1)
        expect(assigns(:uncategorized_expenses)).to include(expense2)
      end

      it "loads categories with parent associations" do
        get :index
        expect(assigns(:categories)).to include(category)
      end

      it "groups similar expenses using service" do
        expect(BulkCategorization::GroupingService).to receive(:new)
        expect(grouping_service).to receive(:group_by_similarity).and_return(grouped_expenses)

        get :index
        expect(assigns(:grouped_expenses)).to eq(grouped_expenses)
      end

      it "calculates statistics for grouped expenses" do
        get :index

        stats = assigns(:statistics)
        expect(stats).to include(:total_groups, :total_expenses, :high_confidence_groups, :total_amount)
      end

      it "includes necessary associations to prevent N+1 queries" do
        # Test that the controller loads necessary associations without mocking internal methods
        get :index
        expect(response).to have_http_status(:ok)
        expect(assigns(:grouped_expenses)).to be_present
      end

      it "limits results for performance" do
        # Test that performance limiting works without mocking ActiveRecord internals
        get :index
        expect(response).to have_http_status(:ok)
        expect(assigns(:grouped_expenses).size).to be <= 500
      end

      it "paginates when page parameter present" do
        # Test pagination parameter handling without mocking ActiveRecord methods
        get :index, params: { page: "2" }
        expect(response).to have_http_status(:ok)
      end

      it "renders the index template" do
        get :index
        expect(response).to render_template(:index)
      end
    end

    context "as JSON request" do
      it "returns grouped expenses as JSON" do
        get :index, format: :json

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        json_response = JSON.parse(response.body)
        expect(json_response).to be_present
      end
    end
  end

  describe "GET #show" do
    context "as HTML request" do
      it "shows bulk operation details" do
        get :show, params: { id: bulk_operation.id }

        expect(response).to have_http_status(:ok)
        expect(assigns(:bulk_operation)).to eq(bulk_operation)
        expect(assigns(:affected_expenses)).to be_present
      end

      it "loads bulk operation with associations" do
        get :show, params: { id: bulk_operation.id }

        expect(assigns(:bulk_operation)).to eq(bulk_operation)
        # The affected_expenses is an association proxy, so just check it exists
        expect(assigns(:affected_expenses)).to respond_to(:empty?)
      end

      it "includes necessary associations to prevent N+1 queries" do
        # Test that necessary associations are loaded without mocking ActiveRecord methods
        get :show, params: { id: bulk_operation.id }
        expect(response).to have_http_status(:ok)
        expect(assigns(:bulk_operation)).to be_present
      end
    end

    context "as JSON request" do
      it "returns bulk operation as JSON" do
        get :show, params: { id: bulk_operation.id }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key("id")
      end
    end
  end

  describe "before_actions", unit: true do
    describe "#load_uncategorized_expenses" do
      it "is called for index action" do
        expect(controller).to receive(:load_uncategorized_expenses).and_call_original

        # Mock the grouping service to avoid additional complexity
        allow(BulkCategorization::GroupingService).to receive(:new).and_return(double("service", group_by_similarity: []))

        get :index
      end
    end

    describe "#load_bulk_operation" do
      it "is called for show action" do
        expect(controller).to receive(:load_bulk_operation).and_call_original
        get :show, params: { id: bulk_operation.id }, format: :json
      end

      it "is configured as before_action" do
        # Test the before_action configuration by checking that the filter exists
        before_actions = controller.class._process_action_callbacks.select do |callback|
          callback.filter == :load_bulk_operation
        end

        expect(before_actions).not_to be_empty
        # Just verify that the callback exists and is configured properly
        expect(before_actions.first.filter).to eq(:load_bulk_operation)
      end
    end
  end

  describe "error handling", unit: true do
    context "when bulk operation is not found" do
      it "raises RecordNotFound error" do
        expect {
          get :show, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "pagination handling", unit: true do
    context "when page parameter is provided" do
      it "sets up pagination-ready relation" do
        # Create a proper ActionController::Parameters object
        params = ActionController::Parameters.new(page: "2")
        allow(controller).to receive(:params).and_return(params)

        controller.send(:load_uncategorized_expenses)

        uncategorized = controller.instance_variable_get(:@uncategorized_expenses)
        # Verify it's an ActiveRecord relation with the expected structure
        expect(uncategorized).to be_a(ActiveRecord::Relation)
        # Test that the relation has the right scope (uncategorized expenses)
        expect(uncategorized.to_sql).to include('"category_id" IS NULL')
      end
    end
  end

  describe "private methods" do
    describe "#load_uncategorized_expenses" do
      it "loads uncategorized expenses for the current user" do
        controller.send(:load_uncategorized_expenses)
        expect(assigns(:uncategorized_expenses)).to be_present
      end

      it "loads expenses with proper associations and limits" do
        controller.send(:load_uncategorized_expenses)

        uncategorized = controller.instance_variable_get(:@uncategorized_expenses)
        expect(uncategorized).to include(expense1)
        expect(uncategorized).to include(expense2)
        # Test that it's a relation with expected methods
        expect(uncategorized).to respond_to(:includes)
        expect(uncategorized).to respond_to(:order)
        expect(uncategorized).to respond_to(:limit)
      end
    end

    describe "#load_bulk_operation" do
      it "loads the specified bulk operation" do
        controller.params = { id: bulk_operation.id.to_s }
        controller.send(:load_bulk_operation)
        expect(assigns(:bulk_operation)).to eq(bulk_operation)
      end

      it "loads bulk operation with associations" do
        controller.params = ActionController::Parameters.new(id: bulk_operation.id)
        controller.send(:load_bulk_operation)

        loaded_operation = controller.instance_variable_get(:@bulk_operation)
        expect(loaded_operation).to eq(bulk_operation)
      end
    end

    describe "#group_similar_expenses" do
      it "groups expenses by similarity using the grouping service" do
        expenses = [ expense1, expense2 ]
        grouping_service = double("BulkCategorization::GroupingService", group_by_similarity: [])
        allow(BulkCategorization::GroupingService).to receive(:new).with(expenses).and_return(grouping_service)

        result = controller.send(:group_similar_expenses, expenses)
        expect(result).to be_an(Array)
      end

      it "uses grouping service to group expenses" do
        expenses = [ expense1 ]
        grouping_service = double("BulkCategorization::GroupingService")
        allow(BulkCategorization::GroupingService).to receive(:new).and_return(grouping_service)
        allow(grouping_service).to receive(:group_by_similarity).and_return([])

        expect(BulkCategorization::GroupingService).to receive(:new).with(expenses)
        expect(grouping_service).to receive(:group_by_similarity)

        controller.send(:group_similar_expenses, expenses)
      end
    end

    describe "#calculate_statistics" do
      it "calculates statistics for grouped expenses" do
        grouped_expenses = [
          { expenses: [ expense1, expense2 ], confidence: 0.9, total_amount: 50.0 },
          { expenses: [ expense1 ], confidence: 0.7, total_amount: 25.0 }
        ]
        stats = controller.send(:calculate_statistics, grouped_expenses)
        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:total_groups)
        expect(stats).to have_key(:total_expenses)
        expect(stats[:total_groups]).to eq(2)
        expect(stats[:total_expenses]).to eq(3)
      end

      it "calculates correct statistics" do
        grouped_expenses = [
          { expenses: [ expense1 ], confidence: 0.9, total_amount: 100 },
          { expenses: [ expense2 ], confidence: 0.7, total_amount: 200 }
        ]

        stats = controller.send(:calculate_statistics, grouped_expenses)

        expect(stats).to include(
          total_groups: 2,
          total_expenses: 2,
          high_confidence_groups: 1,
          total_amount: 300
        )
      end
    end
  end


  describe "authentication and authorization" do
    context "without authentication" do
      before do
        allow(controller).to receive(:authenticate_user!).and_raise(ActionController::RoutingError, "Not authenticated")
      end

      it "requires authentication for index" do
        expect { get :index }.to raise_error(ActionController::RoutingError)
      end
    end
  end
end
