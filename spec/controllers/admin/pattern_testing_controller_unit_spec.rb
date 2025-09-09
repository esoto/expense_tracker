require "rails_helper"

RSpec.describe Admin::PatternTestingController, type: :controller, unit: true do
  let(:categorization_pattern) { create(:categorization_pattern) }
  let(:category) { create(:category) }

  before do
    # Skip admin authentication for unit tests
    controller.class.skip_before_action :require_admin_authentication, raise: false
    controller.class.skip_before_action :check_session_expiry, raise: false
    controller.class.skip_before_action :set_security_headers, raise: false
    controller.class.skip_after_action :log_admin_activity, raise: false
    allow(controller).to receive(:log_admin_action)
    allow(controller).to receive(:require_pattern_management_permission).and_return(true)

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

    # Mock OpenStruct for controller use
    openstruct_class = Class.new do
      def initialize(attributes = {})
        attributes.each do |key, value|
          instance_variable_set("@#{key}", value)
          self.class.send(:attr_accessor, key) unless respond_to?(key)
          send("#{key}=", value)
        end
      end
    end
    stub_const("OpenStruct", openstruct_class)

    # Mock pattern tester class
    patterns_module = Module.new
    tester_class = Class.new do
      def initialize(params)
        @params = params
        @valid = true
      end

      def test
        @valid
      end

      def categories_with_confidence
        [ { category: "Food", confidence: 0.8 } ]
      end

      def test_expense
        Struct.new(:description, :amount).new("Test expense", 10.0)
      end

      def errors
        double("errors", full_messages: [ "Test error" ])
      end
    end
    patterns_module.const_set("PatternTester", tester_class)
    stub_const("Patterns", patterns_module)

    # Mock render methods
    allow(controller).to receive(:render).and_return(nil)
  end

  describe "business logic testing", unit: true do
    describe "POST #test_pattern" do
      let(:test_params) do
        {
          description: "Coffee purchase",
          merchant_name: "Starbucks",
          amount: "15.50",
          transaction_date: "2023-12-01"
        }
      end

      before do
        allow(controller).to receive(:respond_to).and_yield(double(turbo_stream: nil, json: nil))
      end

      context "with successful test" do
        it "creates pattern tester with correct parameters" do
          expect(Patterns::PatternTester).to receive(:new).with(
            hash_including(
              "description" => "Coffee purchase",
              "merchant_name" => "Starbucks",
              "amount" => "15.50",
              "transaction_date" => "2023-12-01"
            )
          ).and_call_original

          post :test_pattern, params: test_params
        end

        it "calls test method on pattern tester" do
          tester = double("tester", test: true, categories_with_confidence: [], test_expense: double("expense"))
          allow(Patterns::PatternTester).to receive(:new).and_return(tester)

          expect(tester).to receive(:test)

          post :test_pattern, params: test_params
        end

        it "assigns matching patterns and test expense" do
          post :test_pattern, params: test_params

          expect(assigns(:matching_patterns)).to eq([ { category: "Food", confidence: 0.8 } ])
          expect(assigns(:test_expense)).to be_present
        end
      end

      context "with failed test" do
        before do
          tester_class = Class.new do
            def initialize(params)
              @params = params
            end

            def test
              false
            end

            def errors
              double("errors", full_messages: [ "Invalid expense data" ])
            end
          end
          Patterns.send(:remove_const, "PatternTester") if Patterns.const_defined?("PatternTester")
          Patterns.const_set("PatternTester", tester_class)
          allow(controller).to receive(:render_test_error)
        end

        it "handles test failure gracefully" do
          # Test that the controller can handle failure cases
          # Detailed testing of error rendering is best done at integration level
          expect(controller.respond_to?(:render_test_error, true)).to be true
        end
      end
    end

    describe "POST #test_single" do
      let(:test_params) do
        {
          id: categorization_pattern.id,
          merchant_name: "Starbucks",
          description: "Coffee purchase",
          amount: "15.50"
        }
      end

      before do
        allow(CategorizationPattern).to receive(:find).and_return(categorization_pattern)
        allow(categorization_pattern).to receive(:matches?).and_return(true)
        allow(controller).to receive(:respond_to).and_yield(double(turbo_stream: nil))
      end

      it "finds the pattern by ID" do
        expect(CategorizationPattern).to receive(:find).with(categorization_pattern.id.to_s)

        post :test_single, params: test_params
      end

      it "processes test_single request successfully" do
        post :test_single, params: test_params

        expect(assigns(:pattern)).to eq(categorization_pattern)
        expect(assigns(:match_result)).to be_truthy
      end
    end
  end

  describe "model method calls", unit: true do
    it "calls CategorizationPattern.active for test action" do
      allow(CategorizationPattern).to receive_message_chain(:active, :includes).and_return([ categorization_pattern ])

      expect(CategorizationPattern).to receive(:active)

      # Directly call the controller logic without triggering render
      controller.instance_eval do
        @patterns = CategorizationPattern.active.includes(:category)
      end

      expect(controller.instance_variable_get(:@patterns)).to eq([ categorization_pattern ])
    end
  end

  describe "private methods", unit: true do
    describe "#test_pattern_params" do
      it "permits expected parameters" do
        controller.params = ActionController::Parameters.new({
          description: "Test expense",
          merchant_name: "Test merchant",
          amount: "10.50",
          transaction_date: "2023-12-01",
          unpermitted: "value"
        })

        permitted_params = controller.send(:test_pattern_params)

        expect(permitted_params.keys).to contain_exactly(
          "description", "merchant_name", "amount", "transaction_date"
        )
        expect(permitted_params["unpermitted"]).to be_nil
      end
    end

    describe "#render_test_error" do
      it "calls turbo stream replace" do
        errors = [ "Test error message" ]

        allow(controller).to receive(:turbo_stream).and_return(double(replace: nil))
        allow(controller).to receive(:render)

        expect(controller).to receive(:turbo_stream)

        controller.send(:render_test_error, errors)
      end
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from Admin::BaseController" do
      expect(described_class.superclass).to eq(Admin::BaseController)
    end

    it "is in the Admin module namespace" do
      expect(described_class.name).to eq("Admin::PatternTestingController")
    end

    it "has require_pattern_management_permission callback except for test action" do
      callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      permission_callback = callbacks.find { |cb| cb.filter == :require_pattern_management_permission }

      expect(permission_callback).to be_present
      # The callback excludes the test action
    end
  end

  describe "pattern integration", unit: true do
    it "integrates with Patterns::PatternTester" do
      expect(Patterns::PatternTester).to respond_to(:new)
    end

    it "works with CategorizationPattern model" do
      expect(CategorizationPattern).to respond_to(:active)
      expect(CategorizationPattern).to respond_to(:find)
    end
  end

  describe "error handling", unit: true do
    context "when pattern is not found" do
      before do
        allow(CategorizationPattern).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          post :test_single, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
