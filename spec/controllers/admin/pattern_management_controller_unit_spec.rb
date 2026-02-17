require "rails_helper"

RSpec.describe Admin::PatternManagementController, type: :controller, unit: true do
  let(:categorization_pattern) { create(:categorization_pattern) }

  let(:admin_user) do
    double("admin_user",
      session_expired?: false,
      extend_session: nil,
      invalidate_session!: nil,
      id: 1,
      email: "admin@test.com",
      can_manage_patterns?: true
    )
  end

  before do
    # Skip admin authentication for unit tests
    controller.class.skip_before_action :require_admin_authentication, raise: false
    controller.class.skip_before_action :check_session_expiry, raise: false
    controller.class.skip_before_action :set_security_headers, raise: false
    controller.class.skip_after_action :log_admin_activity, raise: false
    allow(controller).to receive(:log_admin_action)

    # Mock admin authentication to allow access
    allow(controller).to receive(:current_admin_user).and_return(admin_user)
    allow(controller).to receive(:admin_signed_in?).and_return(true)

    # Mock service classes to avoid actual implementation calls
    services_module = Module.new
    categorization_module = Module.new
    services_module.const_set("Categorization", categorization_module)
    stub_const("Services", services_module)

    importer_class = Class.new do
      def import(file)
        { success: true, imported_count: 5 }
      end
    end
    categorization_module.const_set("PatternImporter", importer_class)

    exporter_class = Class.new do
      def export_to_csv
        "pattern,category\ntest,food"
      end
    end
    categorization_module.const_set("PatternExporter", exporter_class)

    analytics_class = Class.new do
      def generate_statistics
        { total_patterns: 10, active_patterns: 8 }
      end

      def performance_over_time
        [ { date: "2023-01-01", success_rate: 0.8 } ]
      end
    end
    categorization_module.const_set("PatternAnalytics", analytics_class)
  end

  describe "POST #import", unit: true do
    context "with valid file" do
      let(:file) { double("file", original_filename: "test.csv") }

      before do
        allow(controller).to receive(:redirect_to)
      end

      it "calls pattern importer service" do
        importer = double("importer")
        expect(Services::Categorization::PatternImporter).to receive(:new).and_return(importer)
        expect(importer).to receive(:import).and_return({ success: true, imported_count: 5 })

        post :import, params: { file: file }
      end

      it "sets success flash message when import succeeds" do
        post :import, params: { file: file }
        expect(flash[:notice]).to eq("Successfully imported 5 patterns")
      end

      it "redirects to admin patterns path" do
        expect(controller).to receive(:redirect_to)
        post :import, params: { file: file }
      end
    end

    context "with failed import" do
      let(:file) { double("file", original_filename: "invalid.csv") }

      before do
        importer_class = Class.new do
          def import(file)
            { success: false, error: "Invalid format" }
          end
        end
        Services::Categorization.send(:remove_const, "PatternImporter") if Services::Categorization.const_defined?("PatternImporter")
        Services::Categorization.const_set("PatternImporter", importer_class)
        allow(controller).to receive(:redirect_to)
      end

      it "sets error flash message when import fails" do
        post :import, params: { file: file }
        expect(flash[:alert]).to eq("Import failed: Invalid format")
      end
    end

    context "without file" do
      before do
        allow(controller).to receive(:redirect_to)
      end

      it "sets error flash message when no file provided" do
        post :import, params: {}
        expect(flash[:alert]).to eq("Please select a file to import")
      end
    end
  end

  describe "GET #export", unit: true do
    before do
      allow(controller).to receive(:send_data)
    end

    it "calls pattern exporter service" do
      exporter = double("exporter", export_to_csv: "test,data")
      expect(Services::Categorization::PatternExporter).to receive(:new).and_return(exporter)
      expect(exporter).to receive(:export_to_csv)

      get :export, format: :csv
    end

    it "sends CSV data with correct filename and content type" do
      expect(controller).to receive(:send_data).with(
        "pattern,category\ntest,food",
        hash_including(
          filename: /patterns_\d{8}\.csv/,
          type: "text/csv"
        )
      )

      get :export, format: :csv
    end
  end

  describe "GET #statistics", unit: true do
    it "calls pattern analytics service" do
      analytics = double("analytics", generate_statistics: { total_patterns: 10 })
      expect(Services::Categorization::PatternAnalytics).to receive(:new).and_return(analytics)
      expect(analytics).to receive(:generate_statistics)

      get :statistics, format: :json
    end

    it "assigns statistics data" do
      get :statistics, format: :json
      expect(assigns(:stats)).to eq({ total_patterns: 10, active_patterns: 8 })
    end

    it "renders JSON response" do
      allow(controller).to receive(:render)
      expect(controller).to receive(:render).with(json: { total_patterns: 10, active_patterns: 8 })
      get :statistics, format: :json
    end
  end

  describe "GET #performance", unit: true do
    it "calls pattern analytics service for performance data" do
      analytics = double("analytics", performance_over_time: [ { date: "2023-01-01" } ])
      expect(Services::Categorization::PatternAnalytics).to receive(:new).and_return(analytics)
      expect(analytics).to receive(:performance_over_time)

      get :performance, format: :json
    end

    it "assigns performance data" do
      get :performance, format: :json
      expect(assigns(:performance_data)).to eq([ { date: "2023-01-01", success_rate: 0.8 } ])
    end

    it "renders JSON response" do
      allow(controller).to receive(:render)
      expect(controller).to receive(:render).with(json: [ { date: "2023-01-01", success_rate: 0.8 } ])
      get :performance, format: :json
    end
  end

  describe "POST #toggle_active", unit: true do
    before do
      allow(CategorizationPattern).to receive(:find).and_return(categorization_pattern)
      allow(categorization_pattern).to receive(:active).and_return(true)
      allow(categorization_pattern).to receive(:update!)
      allow(controller).to receive(:respond_to).and_yield(double(turbo_stream: nil, html: nil))
      allow(controller).to receive(:redirect_to)
      allow(controller).to receive(:render)
    end

    it "finds the pattern by ID" do
      expect(CategorizationPattern).to receive(:find).with(categorization_pattern.id.to_s)
      post :toggle_active, params: { id: categorization_pattern.id }
    end

    it "toggles the pattern's active state" do
      expect(categorization_pattern).to receive(:update!).with(active: false) # !true = false
      post :toggle_active, params: { id: categorization_pattern.id }
    end

    it "assigns pattern instance variable" do
      post :toggle_active, params: { id: categorization_pattern.id }
      expect(assigns(:pattern)).to eq(categorization_pattern)
    end

    context "with turbo stream format" do
      it "handles turbo stream response" do
        post :toggle_active, params: { id: categorization_pattern.id }, format: :turbo_stream
        expect(categorization_pattern).to have_received(:update!)
      end
    end

    context "with HTML format" do
      it "handles HTML response" do
        post :toggle_active, params: { id: categorization_pattern.id }, format: :html
        expect(categorization_pattern).to have_received(:update!)
      end
    end
  end

  describe "permission checks", unit: true do
    describe "#require_pattern_management_permission" do
      context "when admin user can manage patterns" do
        before do
          allow(admin_user).to receive(:can_manage_patterns?).and_return(true)
        end

        it "allows access for authorized users" do
          # Permission check should not render forbidden
          expect(controller).not_to receive(:render_forbidden)
          controller.send(:require_pattern_management_permission)
        end
      end

      context "when admin user cannot manage patterns" do
        let(:unauthorized_user) do
          double("admin_user",
            session_expired?: false,
            extend_session: nil,
            invalidate_session!: nil,
            id: 2,
            email: "readonly@test.com",
            can_manage_patterns?: false
          )
        end

        before do
          allow(controller).to receive(:current_admin_user).and_return(unauthorized_user)
        end

        it "renders forbidden for unauthorized users" do
          expect(controller).to receive(:render_forbidden).with("You don't have permission to manage patterns.")
          controller.send(:require_pattern_management_permission)
        end
      end
    end

    it "delegates permission check to AdminAuthentication concern" do
      # Verify the controller does NOT define its own require_pattern_management_permission
      # It should use the one from AdminAuthentication concern
      own_methods = described_class.instance_methods(false) +
                    described_class.private_instance_methods(false)
      expect(own_methods).not_to include(:require_pattern_management_permission)
    end
  end

  describe "controller inheritance and configuration", unit: true do
    it "inherits from Admin::BaseController" do
      expect(described_class.superclass).to eq(Admin::BaseController)
    end

    it "is in the Admin module namespace" do
      expect(described_class.name).to eq("Admin::PatternManagementController")
    end

    it "has require_pattern_management_permission callback" do
      callbacks = controller.class._process_action_callbacks.select { |c| c.kind == :before }
      expect(callbacks.map(&:filter)).to include(:require_pattern_management_permission)
    end
  end

  describe "service integration", unit: true do
    it "integrates with PatternImporter service" do
      expect(Services::Categorization::PatternImporter).to respond_to(:new)
    end

    it "integrates with PatternExporter service" do
      expect(Services::Categorization::PatternExporter).to respond_to(:new)
    end

    it "integrates with PatternAnalytics service" do
      expect(Services::Categorization::PatternAnalytics).to respond_to(:new)
    end
  end

  describe "error handling", unit: true do
    context "when pattern is not found" do
      before do
        allow(CategorizationPattern).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          post :toggle_active, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
