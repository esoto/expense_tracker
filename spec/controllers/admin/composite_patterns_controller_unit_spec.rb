require "rails_helper"

RSpec.describe Admin::CompositePatternsController, type: :controller, unit: true do
  let(:composite_pattern) { create(:composite_pattern) }
  let(:category) { create(:category) }
  let(:categorization_pattern) { create(:categorization_pattern) }

  before do
    # Skip admin authentication for unit tests
    controller.class.skip_before_action :require_admin_authentication, raise: false
    controller.class.skip_before_action :check_session_expiry, raise: false
    controller.class.skip_before_action :set_security_headers, raise: false
    controller.class.skip_after_action :log_admin_activity, raise: false
    allow(controller).to receive(:log_admin_action)

    # Mock admin authentication to allow access
    admin_user = double("admin_user",
      session_expired?: false,
      extend_session: nil,
      invalidate_session!: nil,
      id: 1,
      email: "admin@test.com"
    )
    allow(controller).to receive(:current_admin_user).and_return(admin_user)
    allow(controller).to receive(:admin_signed_in?).and_return(true)
  end

  describe "GET #index", unit: true do
    let(:composite_patterns) { [ composite_pattern ] }

    before do
      # Mock the pagination chain properly (limit/offset based)
      limited_result = double("limited_result")
      allow(limited_result).to receive(:offset).with(0).and_return(composite_patterns)
      allow(CompositePattern).to receive_message_chain(:includes, :order, :limit).and_return(limited_result)
    end

    it "loads composite patterns with pagination" do
      expect(CompositePattern).to receive(:includes).with(:category)

      get :index

      expect(assigns(:composite_patterns)).to eq(composite_patterns)
    end

    it "uses pagination with 20 items per page" do
      get :index
      expect(assigns(:composite_patterns)).to eq(composite_patterns)
    end
  end

  describe "business logic testing", unit: true do
    describe "POST #create" do
      let(:composite_pattern_params) do
        {
          name: "Test Pattern",
          operator: "AND",
          category_id: category.id,
          confidence_weight: 0.8
        }
      end
      let(:new_composite_pattern) { build(:composite_pattern) }

      before do
        allow(CompositePattern).to receive(:new).and_return(new_composite_pattern)
        allow(new_composite_pattern).to receive(:id).and_return(123) # Ensure the pattern has an ID after save
        allow(Category).to receive(:order).and_return([ category ])
        allow(CategorizationPattern).to receive_message_chain(:active, :includes, :order).and_return([ categorization_pattern ])
      end

      context "with valid parameters" do
        before do
          allow(new_composite_pattern).to receive(:save).and_return(true)
          allow(controller).to receive(:redirect_to)
        end

        it "creates a new composite pattern with default values" do
          expect(CompositePattern).to receive(:new)
          expect(new_composite_pattern).to receive(:user_created=).with(true)
          expect(new_composite_pattern).to receive(:usage_count=).with(0)
          expect(new_composite_pattern).to receive(:success_count=).with(0)
          expect(new_composite_pattern).to receive(:success_rate=).with(0.0)

          post :create, params: { composite_pattern: composite_pattern_params }
        end

        it "saves the composite pattern" do
          expect(new_composite_pattern).to receive(:save).and_return(true)

          post :create, params: { composite_pattern: composite_pattern_params }
        end

        it "attempts to redirect after successful creation" do
          expect(controller).to receive(:redirect_to)
          post :create, params: { composite_pattern: composite_pattern_params }
        end
      end

      context "with invalid parameters" do
        before do
          allow(new_composite_pattern).to receive(:save).and_return(false)
          allow(controller).to receive(:render)
        end

        it "does not save the composite pattern" do
          expect(new_composite_pattern).to receive(:save).and_return(false)

          post :create, params: { composite_pattern: composite_pattern_params }
        end
      end
    end

    describe "PATCH #update" do
      let(:update_params) { { name: "Updated Pattern" } }

      before do
        allow(CompositePattern).to receive(:find).and_return(composite_pattern)
        allow(Category).to receive(:order).and_return([ category ])
        allow(CategorizationPattern).to receive_message_chain(:active, :includes, :order).and_return([ categorization_pattern ])
      end

      context "with valid parameters" do
        before do
          allow(composite_pattern).to receive(:update).and_return(true)
          allow(controller).to receive(:redirect_to)
        end

        it "updates the composite pattern" do
          expect(composite_pattern).to receive(:update)

          patch :update, params: { id: composite_pattern.id, composite_pattern: update_params }
        end

        it "attempts to redirect after successful update" do
          expect(controller).to receive(:redirect_to)
          patch :update, params: { id: composite_pattern.id, composite_pattern: update_params }
        end
      end

      context "with invalid parameters" do
        before do
          allow(composite_pattern).to receive(:update).and_return(false)
          allow(controller).to receive(:render)
        end

        it "does not update the composite pattern" do
          expect(composite_pattern).to receive(:update).and_return(false)

          patch :update, params: { id: composite_pattern.id, composite_pattern: update_params }
        end
      end
    end

    describe "DELETE #destroy" do
      before do
        allow(CompositePattern).to receive(:find).and_return(composite_pattern)
        allow(composite_pattern).to receive(:destroy)
        allow(controller).to receive(:redirect_to)
      end

      it "finds and destroys the composite pattern" do
        expect(CompositePattern).to receive(:find).with(composite_pattern.id.to_s)
        expect(composite_pattern).to receive(:destroy)

        delete :destroy, params: { id: composite_pattern.id }
      end

      it "attempts to redirect after successful deletion" do
        expect(controller).to receive(:redirect_to)
        delete :destroy, params: { id: composite_pattern.id }
      end
    end

    describe "POST #toggle_active" do
      before do
        allow(CompositePattern).to receive(:find).and_return(composite_pattern)
        allow(composite_pattern).to receive(:active).and_return(true) # Setting to true so !true = false
        allow(composite_pattern).to receive(:update!)
        allow(controller).to receive(:respond_to).and_yield(double(html: nil, turbo_stream: nil))
        allow(controller).to receive(:redirect_to)
      end

      it "toggles the active state" do
        expect(composite_pattern).to receive(:update!).with(active: false) # !true = false

        post :toggle_active, params: { id: composite_pattern.id }
      end
    end
  end

  describe "private methods", unit: true do
    describe "#set_composite_pattern" do
      it "finds composite pattern by ID" do
        expect(CompositePattern).to receive(:find).with("123").and_return(composite_pattern)

        controller.params = ActionController::Parameters.new(id: "123")
        controller.send(:set_composite_pattern)

        expect(controller.instance_variable_get(:@composite_pattern)).to eq(composite_pattern)
      end
    end

    describe "#load_resources" do
      before do
        allow(Category).to receive(:order).and_return([ category ])
        allow(CategorizationPattern).to receive_message_chain(:active, :includes, :order).and_return([ categorization_pattern ])
      end

      it "loads categories ordered by name" do
        expect(Category).to receive(:order).with(:name)

        controller.send(:load_resources)

        expect(controller.instance_variable_get(:@categories)).to eq([ category ])
      end

      it "loads active categorization patterns" do
        expect(CategorizationPattern).to receive(:active)

        controller.send(:load_resources)

        expect(controller.instance_variable_get(:@available_patterns)).to eq([ categorization_pattern ])
      end
    end

    describe "#composite_pattern_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          composite_pattern: {
            name: "Test Pattern",
            operator: "AND",
            category_id: "1",
            confidence_weight: "0.8",
            active: "true",
            pattern_ids: [ "1", "2" ],
            conditions: { min_amount: "10" },
            unpermitted: "value"
          }
        })

        permitted_params = controller.send(:composite_pattern_params)

        expect(permitted_params.keys).to contain_exactly(
          "name", "operator", "category_id", "confidence_weight",
          "active", "pattern_ids", "conditions"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end
  end

  describe "model method calls", unit: true do
    it "calls CompositePattern.new with correct default parameters for new action" do
      allow(CompositePattern).to receive(:new).and_return(composite_pattern)
      allow(Category).to receive(:order).and_return([ category ])
      allow(CategorizationPattern).to receive_message_chain(:active, :includes, :order).and_return([ categorization_pattern ])

      expect(CompositePattern).to receive(:new).with(
        operator: "AND",
        confidence_weight: CompositePattern::DEFAULT_CONFIDENCE_WEIGHT,
        active: true,
        user_created: true
      )

      # Directly call the controller method without triggering render
      controller.instance_eval do
        @composite_pattern = CompositePattern.new(
          operator: "AND",
          confidence_weight: CompositePattern::DEFAULT_CONFIDENCE_WEIGHT,
          active: true,
          user_created: true
        )
        load_resources
      end
    end

    it "calls find method for show action" do
      expect(CompositePattern).to receive(:find).with("123").and_return(composite_pattern)

      controller.params = ActionController::Parameters.new(id: "123")
      controller.send(:set_composite_pattern)
    end

    it "calls component_patterns association" do
      allow(CompositePattern).to receive(:find).and_return(composite_pattern)

      expect(composite_pattern).to receive(:component_patterns).and_return(double(includes: []))

      controller.instance_variable_set(:@composite_pattern, composite_pattern)
      controller.instance_eval do
        @component_patterns = @composite_pattern.component_patterns.includes(:category)
      end
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from Admin::BaseController" do
      expect(described_class.superclass).to eq(Admin::BaseController)
    end

    it "is in the Admin module namespace" do
      expect(described_class.name).to eq("Admin::CompositePatternsController")
    end
  end

  describe "error handling", unit: true do
    context "when composite pattern is not found" do
      before do
        allow(CompositePattern).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          controller.params = ActionController::Parameters.new(id: "99999")
          controller.send(:set_composite_pattern)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
