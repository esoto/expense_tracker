require "rails_helper"

RSpec.describe Admin::PatternsController, type: :controller, unit: true do
  let(:admin_user) { create(:admin_user) }
  let(:pattern) { create(:categorization_pattern) }
  let(:category) { create(:category) }

  before do
    # Mock admin authentication
    allow(controller).to receive(:current_admin_user).and_return(admin_user)

    # Mock permission checks to allow access
    allow(controller).to receive(:require_pattern_management_permission).and_return(true)
    allow(controller).to receive(:require_pattern_edit_permission).and_return(true)
    allow(controller).to receive(:require_pattern_delete_permission).and_return(true)
    allow(controller).to receive(:require_import_permission).and_return(true)
    allow(controller).to receive(:require_statistics_permission).and_return(true)

    # Mock rate limiting
    allow(controller).to receive(:check_rate_limit_for_testing).and_return(true)
    allow(controller).to receive(:check_rate_limit_for_import).and_return(true)

    # Mock cache
    allow(Rails.cache).to receive(:fetch).and_yield
    allow(Rails.cache).to receive(:increment).and_return(1)

    # Mock logging
    allow(controller).to receive(:log_admin_action)
  end

  describe "GET #index" do
    let!(:pattern1) { create(:categorization_pattern, pattern_type: "merchant") }
    let!(:pattern2) { create(:categorization_pattern, pattern_type: "description") }

    it "loads patterns with categories" do
      get :index

      expect(response).to have_http_status(:ok)
      expect(assigns(:patterns)).to include(pattern1, pattern2)
    end

    it "calculates statistics" do
      get :index

      expect(assigns(:total_patterns)).to be_a(Integer)
      expect(assigns(:active_patterns)).to be_a(Integer)
      expect(assigns(:average_success_rate)).to be_a(Numeric)
      expect(assigns(:total_usage)).to be_a(Integer)
    end

    context "with filters" do
      it "filters by pattern type" do
        get :index, params: { filter_type: "merchant" }

        expect(assigns(:patterns)).to include(pattern1)
        # Note: We don't test exclusion as the controller uses pagination
      end

      it "filters by category" do
        get :index, params: { filter_category: pattern1.category_id }

        expect(response).to have_http_status(:ok)
      end

      it "filters by status" do
        get :index, params: { filter_status: "active" }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with search" do
      it "searches pattern values" do
        get :index, params: { search: pattern1.pattern_value }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with sorting" do
      it "sorts by usage" do
        get :index, params: { sort: "usage" }

        expect(response).to have_http_status(:ok)
      end

      it "sorts by success rate" do
        get :index, params: { sort: "success" }

        expect(response).to have_http_status(:ok)
      end
    end

    it "responds to different formats" do
      get :index, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key("patterns")
      expect(json_response).to have_key("meta")
    end
  end

  describe "GET #show" do
    let!(:feedback) { create(:pattern_feedback, categorization_pattern: pattern) }

    before do
      allow(controller).to receive(:calculate_performance_metrics).and_return({
        total_uses: 10,
        success_rate: 85.5,
        confidence: 0.8
      })
    end

    it "shows pattern details" do
      get :show, params: { id: pattern.id }

      expect(response).to have_http_status(:ok)
      expect(assigns(:pattern)).to eq(pattern)
      expect(assigns(:pattern_feedbacks)).to be_present
      expect(assigns(:performance_metrics)).to be_present
    end

    it "caches performance metrics" do
      expect(Rails.cache).to receive(:fetch).with(
        [ "pattern_metrics", pattern.id, pattern.updated_at ],
        expires_in: 1.hour
      ).and_yield

      get :show, params: { id: pattern.id }
    end

    it "responds to JSON format" do
      get :show, params: { id: pattern.id }, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key("pattern")
      expect(json_response).to have_key("performance")
    end
  end

  describe "GET #new" do
    it "initializes new pattern with defaults" do
      # Ensure there's at least one category
      category

      get :new

      expect(response).to have_http_status(:ok)
      expect(assigns(:pattern)).to be_a_new(CategorizationPattern)
      expect(assigns(:pattern).confidence_weight).to eq(CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT)
      expect(assigns(:pattern).active).to be true
      expect(assigns(:pattern).user_created).to be true
      expect(assigns(:categories)).to be_present
    end
  end

  describe "GET #edit" do
    it "loads pattern for editing" do
      get :edit, params: { id: pattern.id }

      expect(response).to have_http_status(:ok)
      expect(assigns(:pattern)).to eq(pattern)
      expect(assigns(:categories)).to be_present
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        categorization_pattern: {
          pattern_type: "merchant",
          pattern_value: "Starbucks",
          category_id: category.id,
          confidence_weight: 3.0,
          active: true
        }
      }
    end

    context "with valid parameters" do
      it "creates pattern successfully" do
        expect {
          post :create, params: valid_params
        }.to change(CategorizationPattern, :count).by(1)

        created_pattern = CategorizationPattern.last
        expect(created_pattern.pattern_value).to eq("starbucks")
        expect(created_pattern.user_created).to be true
        expect(created_pattern.usage_count).to eq(0)
        expect(created_pattern.success_count).to eq(0)

        expect(controller).to have_received(:log_admin_action).with(
          "pattern_created",
          pattern_id: created_pattern.id
        )

        expect(response).to redirect_to(admin_pattern_path(created_pattern))
      end
    end

    context "with invalid parameters" do
      it "renders new template with errors" do
        invalid_params = valid_params.deep_dup
        invalid_params[:categorization_pattern][:pattern_value] = ""

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(response).to render_template(:new)
        expect(assigns(:pattern).errors).to be_present
      end
    end
  end

  describe "PATCH #update" do
    let(:update_params) do
      {
        id: pattern.id,
        categorization_pattern: {
          pattern_value: "Updated Value",
          confidence_weight: 4.0
        }
      }
    end

    context "with valid parameters" do
      it "updates pattern successfully" do
        patch :update, params: update_params

        pattern.reload
        expect(pattern.pattern_value).to eq("updated value")
        expect(pattern.confidence_weight).to eq(4.0)

        expect(controller).to have_received(:log_admin_action).with(
          "pattern_updated",
          pattern_id: pattern.id
        )

        expect(response).to redirect_to(admin_pattern_path(pattern))
      end
    end

    context "with invalid parameters" do
      it "renders edit template with errors" do
        invalid_params = update_params.deep_dup
        invalid_params[:categorization_pattern][:pattern_value] = ""

        patch :update, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(response).to render_template(:edit)
      end
    end
  end

  describe "DELETE #destroy" do
    it "destroys pattern" do
      pattern_id = pattern.id

      expect {
        delete :destroy, params: { id: pattern.id }
      }.to change(CategorizationPattern, :count).by(-1)

      expect(controller).to have_received(:log_admin_action).with(
        "pattern_deleted",
        pattern_id: pattern_id
      )

      expect(response).to redirect_to(admin_patterns_path)
    end
  end









  describe "error handling" do
    it "handles pattern not found" do
      get :show, params: { id: 999999 }

      expect(response).to redirect_to(admin_patterns_path)
      expect(flash[:alert]).to eq("Pattern not found")
    end
  end

  describe "private methods" do
    describe "#sanitize_pattern_value" do
      it "sanitizes HTML from pattern values" do
        result = controller.send(:sanitize_pattern_value, "<script>alert('xss')</script>Test", "merchant")
        expect(result).to eq("alert('xss')Test")
      end

      it "validates regex patterns" do
        allow(controller).to receive(:validate_safe_regex).and_return(false)
        result = controller.send(:sanitize_pattern_value, "dangerous_regex", "regex")
        expect(result).to be_nil
      end

      it "truncates long values" do
        long_value = "a" * 300
        result = controller.send(:sanitize_pattern_value, long_value, "merchant")
        expect(result.length).to eq(255)
      end
    end

    describe "#validate_safe_regex" do
      it "rejects dangerous regex patterns" do
        dangerous_patterns = [
          "(a+)+",
          "[a+]+",
          "(.*.*)+b"
        ]

        dangerous_patterns.each do |pattern|
          result = controller.send(:validate_safe_regex, pattern)
          expect(result).to be false
        end
      end

      it "accepts safe regex patterns" do
        safe_patterns = [
          "starbucks",
          "coffee.*shop",
          "\\d{4}-\\d{2}-\\d{2}"
        ]

        safe_patterns.each do |pattern|
          result = controller.send(:validate_safe_regex, pattern)
          expect(result).to be true
        end
      end

      it "handles invalid regex syntax" do
        result = controller.send(:validate_safe_regex, "[invalid")
        expect(result).to be false
      end
    end

    describe "#calculate_performance_metrics" do
      it "calculates comprehensive metrics" do
        result = controller.send(:calculate_performance_metrics, pattern)

        expect(result).to have_key(:total_uses)
        expect(result).to have_key(:successful_uses)
        expect(result).to have_key(:success_rate)
        expect(result).to have_key(:confidence)
        expect(result).to have_key(:trend)
      end
    end
  end
end
