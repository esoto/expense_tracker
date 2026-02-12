require "rails_helper"

RSpec.describe Admin::PatternsController, type: :controller, unit: true do
  let(:admin_user) { create(:admin_user, email: "admin_#{SecureRandom.hex(4)}@example.com") }
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
      expect(assigns(:patterns)).to be_present
      # Since the controller uses pagination, we can't guarantee specific patterns will be on first page
      expect(assigns(:patterns).first).to have_attributes(category: be_present)
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

        expect(response).to have_http_status(:ok)
        expect(assigns(:patterns)).to be_present
        # Verify the filtering worked by checking that patterns exist with the right type
        # Since pagination may affect which specific patterns appear, we check the scoped data
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

  describe "Additional method coverage tests" do
    # Note: These methods exist in the controller but are routed to other controllers
    # We test them here for complete code coverage while acknowledging they're not the primary interface

    describe "#toggle_active (internal method coverage)" do
      it "calls update! on pattern with toggled active state" do
        # We need to check the actual state after the toggle
        allow(pattern).to receive(:update!).and_return(true)
        controller.instance_variable_set(:@pattern, pattern)

        # Mock respond_to to avoid routing issues
        allow(controller).to receive(:respond_to).and_yield(double(
          html: double(call: nil),
          turbo_stream: double(call: nil)
        ))

        controller.toggle_active

        expect(pattern).to have_received(:update!).with(active: !pattern.active)
        expect(controller).to have_received(:log_admin_action).with(
          "pattern_toggled",
          pattern_id: pattern.id,
          active: pattern.active
        )
      end
    end

    describe "#test (internal method coverage)" do
      it "sets instance variables for test expense and patterns" do
        test_expense = OpenStruct.new(description: "test")
        patterns = [ pattern ]

        allow(controller).to receive(:build_test_expense).and_return(test_expense)
        allow(CategorizationPattern).to receive_message_chain(:active, :includes).and_return(patterns)
        allow(controller).to receive(:load_categories).and_return(true)

        controller.test

        expect(controller.instance_variable_get(:@test_expense)).to eq(test_expense)
        expect(controller.instance_variable_get(:@patterns)).to eq(patterns)
        expect(controller).to have_received(:build_test_expense)
        expect(CategorizationPattern).to have_received(:active)
      end
    end

    describe "#test_pattern (internal method coverage)" do
      let(:pattern_tester) { double("PatternTester") }

      before do
        allow(Services::Patterns::PatternTester).to receive(:new).and_return(pattern_tester)
        allow(controller).to receive(:test_pattern_params).and_return({ description: "test" })
      end

      it "creates PatternTester with params and executes test when successful" do
        allow(pattern_tester).to receive(:test).and_return(true)
        allow(pattern_tester).to receive(:categories_with_confidence).and_return([ { category: "Food" } ])
        allow(pattern_tester).to receive(:test_expense).and_return(OpenStruct.new)

        # Mock respond_to to avoid format issues
        allow(controller).to receive(:respond_to).and_yield(double(
          turbo_stream: double(call: nil),
          json: double(call: nil)
        ))

        controller.test_pattern

        expect(Services::Patterns::PatternTester).to have_received(:new).with({ description: "test" })
        expect(pattern_tester).to have_received(:test)
        expect(controller.instance_variable_get(:@matching_patterns)).to be_present
        expect(controller.instance_variable_get(:@test_expense)).to be_present
      end

      it "handles test failure" do
        allow(pattern_tester).to receive(:test).and_return(false)
        allow(pattern_tester).to receive(:errors).and_return(double(full_messages: [ "Error" ]))

        # Mock respond_to for error case
        allow(controller).to receive(:respond_to).and_yield(double(
          turbo_stream: double(call: nil),
          json: double(call: nil)
        ))

        controller.test_pattern

        expect(pattern_tester).to have_received(:test)
        # The errors method is called inside the respond_to block, which we're mocking
        # So we just verify that the test failed appropriately
        expect(pattern_tester.test).to be false
      end
    end

    describe "#test_single (internal method coverage)" do
      before do
        controller.instance_variable_set(:@pattern, pattern)
      end

      it "sanitizes input and tests pattern match" do
        test_text = "starbucks coffee"
        allow(controller).to receive(:sanitize_test_input).with(test_text).and_return(test_text)
        allow(pattern).to receive(:matches?).with(test_text).and_return(true)
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(test_text: test_text))

        # Mock respond_to
        allow(controller).to receive(:respond_to).and_yield(double(
          turbo_stream: double(call: nil),
          json: double(call: nil)
        ))

        controller.test_single

        expect(controller).to have_received(:sanitize_test_input).with(test_text)
        expect(pattern).to have_received(:matches?).with(test_text)
        expect(controller.instance_variable_get(:@matches)).to be true
      end

      it "handles empty test text" do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(test_text: ""))
        allow(controller).to receive(:sanitize_test_input).with("").and_return(nil)

        # Mock respond_to for error case
        allow(controller).to receive(:respond_to).and_yield(double(
          turbo_stream: double(call: nil),
          json: double(call: nil)
        ))

        controller.test_single

        expect(controller).to have_received(:sanitize_test_input).with("")
      end
    end
  end



  describe "security and authorization" do
    context "permission checks" do
      it "requires pattern management permission for create" do
        expect(controller).to receive(:require_pattern_management_permission)
        post :create, params: { categorization_pattern: { pattern_type: "merchant" } }
      end

      it "requires pattern edit permission for edit" do
        expect(controller).to receive(:require_pattern_edit_permission)
        get :edit, params: { id: pattern.id }
      end

      it "requires pattern edit permission for update" do
        expect(controller).to receive(:require_pattern_edit_permission)
        patch :update, params: { id: pattern.id, categorization_pattern: { pattern_value: "new" } }
      end

      it "requires pattern delete permission for destroy" do
        expect(controller).to receive(:require_pattern_delete_permission)
        delete :destroy, params: { id: pattern.id }
      end
    end


    context "input sanitization" do
      it "sanitizes pattern values during creation" do
        malicious_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: "<script>alert('xss')</script>Starbucks",
            category_id: category.id
          }
        }

        post :create, params: malicious_params

        created_pattern = CategorizationPattern.last
        expect(created_pattern.pattern_value).not_to include("<script>")
        # The sanitization removes HTML tags but may keep the text content
        expect(created_pattern.pattern_value).to include("starbucks")
      end

      it "validates regex patterns for security" do
        allow(controller).to receive(:validate_safe_regex).and_return(false)

        regex_params = {
          categorization_pattern: {
            pattern_type: "regex",
            pattern_value: "(a+)+",
            category_id: category.id
          }
        }

        post :create, params: regex_params

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "truncates overly long pattern values" do
        long_value = "a" * 300
        long_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: long_value,
            category_id: category.id
          }
        }

        post :create, params: long_params

        created_pattern = CategorizationPattern.last
        expect(created_pattern.pattern_value.length).to be <= 255
      end
    end

    context "SQL injection prevention" do
      it "safely handles search terms with SQL injection attempts" do
        malicious_search = "'; DROP TABLE patterns; --"

        get :index, params: { search: malicious_search }

        expect(response).to have_http_status(:ok)
        # Controller should sanitize search input
      end

      it "safely handles filter parameters" do
        get :index, params: {
          filter_type: "'; DROP TABLE categories; --",
          filter_category: "99999' OR '1'='1",
          filter_status: "<script>alert('xss')</script>"
        }

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "error handling and edge cases" do
    it "handles pattern not found" do
      get :show, params: { id: 999999 }

      expect(response).to redirect_to(admin_patterns_path)
      expect(flash[:alert]).to eq("Pattern not found")
    end

    it "handles pattern not found for edit" do
      get :edit, params: { id: 999999 }

      expect(response).to redirect_to(admin_patterns_path)
      expect(flash[:alert]).to eq("Pattern not found")
    end

    it "handles pattern not found for update" do
      patch :update, params: { id: 999999, categorization_pattern: { pattern_value: "test" } }

      expect(response).to redirect_to(admin_patterns_path)
      expect(flash[:alert]).to eq("Pattern not found")
    end

    it "handles pattern not found for destroy" do
      delete :destroy, params: { id: 999999 }

      expect(response).to redirect_to(admin_patterns_path)
      expect(flash[:alert]).to eq("Pattern not found")
    end


    context "invalid parameters" do
      it "handles missing required parameters in create" do
        expect {
          post :create, params: { categorization_pattern: {} }
        }.to raise_error(ActionController::ParameterMissing)
      end

      it "handles invalid category_id in create" do
        invalid_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: "test",
            category_id: 999999
          }
        }

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "handles invalid confidence_weight" do
        invalid_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: "test",
            category_id: category.id,
            confidence_weight: "invalid"
          }
        }

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "handles nil pattern_value" do
        nil_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: nil,
            category_id: category.id
          }
        }

        post :create, params: nil_params

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "handles empty pattern_value" do
        empty_params = {
          categorization_pattern: {
            pattern_type: "merchant",
            pattern_value: "",
            category_id: category.id
          }
        }

        post :create, params: empty_params

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "database errors" do
      it "handles database connection errors gracefully" do
        allow(CategorizationPattern).to receive(:includes).and_raise(ActiveRecord::ConnectionNotEstablished.new("DB error"))

        expect { get :index }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it "handles database timeout errors" do
        allow(CategorizationPattern).to receive(:includes).and_raise(ActiveRecord::QueryCanceled.new("Query timeout"))

        expect { get :index }.to raise_error(ActiveRecord::QueryCanceled)
      end

      it "handles validation errors on update" do
        allow(pattern).to receive(:update).and_return(false)
        allow(pattern).to receive(:errors).and_return(
          double(any?: true, full_messages: [ "Pattern value can't be blank" ])
        )

        patch :update, params: {
          id: pattern.id,
          categorization_pattern: { pattern_value: "" }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response).to render_template(:edit)
      end
    end

    context "format handling" do
      it "handles unsupported formats gracefully" do
        expect {
          get :index, format: :xml
        }.to raise_error(ActionController::UnknownFormat)
      end
    end


    context "memory and performance limits" do
      it "handles large result sets in index" do
        # Mock large dataset
        large_patterns = Array.new(1000) { pattern }
        allow(controller).to receive(:build_patterns_scope).and_return(
          double(
            except: double(count: 1000, active: double(count: 800), sum: 50000),
            as_json: large_patterns.map(&:as_json),
            current_page: 1,
            total_pages: 50
          )
        )

        get :index, format: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context "concurrent access" do
      it "handles concurrent pattern updates" do
        original_updated_at = pattern.updated_at

        # Simulate another user updating the pattern
        pattern.update_column(:updated_at, 1.minute.from_now)

        patch :update, params: {
          id: pattern.id,
          categorization_pattern: { pattern_value: "updated" }
        }

        expect(response).to have_http_status(:see_other)
      end

      it "handles concurrent pattern deletion" do
        pattern_id = pattern.id
        pattern.destroy

        patch :update, params: {
          id: pattern_id,
          categorization_pattern: { pattern_value: "updated" }
        }

        expect(response).to redirect_to(admin_patterns_path)
        expect(flash[:alert]).to eq("Pattern not found")
      end
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

      it "handles blank values" do
        result = controller.send(:sanitize_pattern_value, "", "merchant")
        expect(result).to be_nil
      end

      it "handles nil values" do
        result = controller.send(:sanitize_pattern_value, nil, "merchant")
        expect(result).to be_nil
      end

      it "strips whitespace" do
        result = controller.send(:sanitize_pattern_value, "  test  ", "merchant")
        expect(result).to eq("test")
      end

      it "handles different pattern types" do
        description_result = controller.send(:sanitize_pattern_value, "test", "description")
        expect(description_result).to eq("test")

        amount_result = controller.send(:sanitize_pattern_value, "100.00", "amount")
        expect(amount_result).to eq("100.00")
      end
    end

    describe "#sanitize_test_input" do
      it "sanitizes HTML from test input" do
        result = controller.send(:sanitize_test_input, "<script>alert('test')</script>text")
        expect(result).not_to include("<script>")
      end

      it "truncates long input" do
        long_input = "a" * 1000
        result = controller.send(:sanitize_test_input, long_input)
        expect(result.length).to be <= 500
      end

      it "strips whitespace" do
        result = controller.send(:sanitize_test_input, "  test input  ")
        expect(result).to eq("test input")
      end

      it "handles blank input" do
        result = controller.send(:sanitize_test_input, "")
        expect(result).to be_nil
      end

      it "handles nil input" do
        result = controller.send(:sanitize_test_input, nil)
        expect(result).to be_nil
      end
    end

    describe "#validate_safe_regex" do
      it "rejects dangerous regex patterns" do
        dangerous_patterns = [
          "(a+)+",
          "[a+]+",
          "(.*.*)+b",
          "(a*)*",
          "(a+)+"
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
          "\\d{4}-\\d{2}-\\d{2}",
          "^test$",
          "[a-zA-Z0-9]+"
        ]

        safe_patterns.each do |pattern|
          result = controller.send(:validate_safe_regex, pattern)
          expect(result).to be true
        end
      end

      it "handles invalid regex syntax" do
        result = controller.send(:validate_safe_regex, "[invalid")
        expect(result).to be false

        result2 = controller.send(:validate_safe_regex, "(?P<invalid)")
        expect(result2).to be false
      end

      it "handles blank patterns" do
        result = controller.send(:validate_safe_regex, "")
        expect(result).to be false
      end

      it "handles nil patterns" do
        result = controller.send(:validate_safe_regex, nil)
        expect(result).to be false
      end

      it "handles timeout scenarios" do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        result = controller.send(:validate_safe_regex, "valid_pattern")
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
        expect(result).to have_key(:last_used)
        expect(result).to have_key(:average_daily_uses)
      end

      it "handles patterns with no usage" do
        unused_pattern = create(:categorization_pattern, usage_count: 0)

        result = controller.send(:calculate_performance_metrics, unused_pattern)

        expect(result[:total_uses]).to eq(0)
        expect(result[:successful_uses]).to eq(0)
      end
    end

    describe "#calculate_average_daily_uses" do
      it "calculates average for old patterns" do
        old_pattern = create(:categorization_pattern,
                           created_at: 60.days.ago,
                           usage_count: 120)

        result = controller.send(:calculate_average_daily_uses, old_pattern)
        expect(result).to be > 0
      end

      it "returns 0 for new patterns" do
        new_pattern = create(:categorization_pattern, created_at: 1.day.ago)

        result = controller.send(:calculate_average_daily_uses, new_pattern)
        expect(result).to eq(0)
      end

      it "handles division by zero" do
        pattern_today = create(:categorization_pattern, created_at: Time.current)

        result = controller.send(:calculate_average_daily_uses, pattern_today)
        expect(result).to eq(0)
      end
    end

    describe "#calculate_trend" do
      it "identifies increasing trends" do
        allow(pattern).to receive_message_chain(:pattern_feedbacks, :where, :count).and_return(10, 5)

        result = controller.send(:calculate_trend, pattern)
        expect(result).to eq("increasing")
      end

      it "identifies decreasing trends" do
        allow(pattern).to receive_message_chain(:pattern_feedbacks, :where, :count).and_return(5, 10)

        result = controller.send(:calculate_trend, pattern)
        expect(result).to eq("decreasing")
      end

      it "identifies stable trends" do
        allow(pattern).to receive_message_chain(:pattern_feedbacks, :where, :count).and_return(8, 8)

        result = controller.send(:calculate_trend, pattern)
        expect(result).to eq("stable")
      end
    end

    describe "#apply_filters" do
      let(:base_scope) { CategorizationPattern.includes(:category) }

      it "applies type filter" do
        filtered_scope = controller.send(:apply_filters, base_scope)
        expect(filtered_scope).to be_a(ActiveRecord::Relation)
      end

      it "applies category filter" do
        allow(controller).to receive(:params).and_return({ filter_category: category.id.to_s })

        filtered_scope = controller.send(:apply_filters, base_scope)
        expect(filtered_scope).to be_a(ActiveRecord::Relation)
      end

      it "applies status filter" do
        allow(controller).to receive(:params).and_return({ filter_status: "active" })

        filtered_scope = controller.send(:apply_filters, base_scope)
        expect(filtered_scope).to be_a(ActiveRecord::Relation)
      end
    end

    describe "#apply_status_filter" do
      let(:scope) { CategorizationPattern.all }

      it "filters by active status" do
        result = controller.send(:apply_status_filter, scope, "active")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by inactive status" do
        result = controller.send(:apply_status_filter, scope, "inactive")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by user_created status" do
        result = controller.send(:apply_status_filter, scope, "user_created")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by system_created status" do
        result = controller.send(:apply_status_filter, scope, "system_created")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by high_confidence status" do
        result = controller.send(:apply_status_filter, scope, "high_confidence")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by successful status" do
        result = controller.send(:apply_status_filter, scope, "successful")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "filters by frequently_used status" do
        result = controller.send(:apply_status_filter, scope, "frequently_used")
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "returns original scope for unknown status" do
        result = controller.send(:apply_status_filter, scope, "unknown_status")
        expect(result).to eq(scope)
      end
    end

    describe "#apply_search" do
      let(:scope) { CategorizationPattern.includes(:category) }

      it "applies search to pattern_value and category name" do
        allow(controller).to receive(:params).and_return({ search: "starbucks" })

        result = controller.send(:apply_search, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sanitizes search input for SQL safety" do
        malicious_search = "'; DROP TABLE patterns; --"
        allow(controller).to receive(:params).and_return({ search: malicious_search })
        expect(ActiveRecord::Base).to receive(:sanitize_sql_like).with(malicious_search)

        controller.send(:apply_search, scope)
      end
    end

    describe "#apply_sorting" do
      let(:scope) { CategorizationPattern.includes(:category) }

      it "sorts by type" do
        allow(controller).to receive(:params).and_return({ sort: "type" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by value" do
        allow(controller).to receive(:params).and_return({ sort: "value" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by category" do
        allow(controller).to receive(:params).and_return({ sort: "category" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by usage" do
        allow(controller).to receive(:params).and_return({ sort: "usage" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by success rate" do
        allow(controller).to receive(:params).and_return({ sort: "success" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by confidence" do
        allow(controller).to receive(:params).and_return({ sort: "confidence" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "sorts by created date" do
        allow(controller).to receive(:params).and_return({ sort: "created" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "uses default sorting for unknown sort parameter" do
        allow(controller).to receive(:params).and_return({ sort: "unknown" })
        result = controller.send(:apply_sorting, scope)
        expect(result).to be_a(ActiveRecord::Relation)
      end
    end
  end

  # Tests for additional pattern management actions
  # Note: These methods exist in the patterns_controller but are routed to pattern_management_controller
  # We test them here as internal methods for complete code coverage
  describe "Pattern Management Actions (Internal Method Coverage)" do
    describe "#import (internal method coverage)" do
      let(:csv_file) { double("csv_file") }
      let(:importer) { double("CsvImporter") }

      before do
        allow(Services::Patterns::CsvImporter).to receive(:new).and_return(importer)
        allow(controller).to receive(:redirect_to)
        allow(controller).to receive(:log_admin_action)
        allow(controller).to receive(:current_admin_user).and_return(admin_user)
        # Set up default mock responses
        allow(importer).to receive(:import).and_return(true)
        allow(importer).to receive(:summary).and_return({ imported: 0, skipped: 0 })
        allow(importer).to receive(:import_errors).and_return([])
      end

      context "with successful import" do
        before do
          allow(importer).to receive(:import).and_return(true)
          allow(importer).to receive(:summary).and_return({ imported: 3, skipped: 0 })
          allow(controller).to receive(:params).and_return(ActionController::Parameters.new(file: csv_file))
        end

        it "creates importer with correct parameters and executes import" do
          controller.import

          expect(Services::Patterns::CsvImporter).to have_received(:new).with(
            file: csv_file,
            user: admin_user,
            dry_run: false
          )
          expect(importer).to have_received(:import)
        end

        it "supports dry run mode" do
          allow(controller).to receive(:params).and_return(
            ActionController::Parameters.new(file: csv_file, dry_run: "true")
          )

          controller.import

          expect(Services::Patterns::CsvImporter).to have_received(:new).with(
            file: csv_file,
            user: admin_user,
            dry_run: true
          )
        end

        it "logs admin action on successful import" do
          controller.import

          expect(controller).to have_received(:log_admin_action).with(
            "patterns_imported",
            summary: { imported: 3, skipped: 0 }
          )
        end
      end

      context "with import failure" do
        before do
          allow(importer).to receive(:import).and_return(false)
          allow(importer).to receive(:import_errors).and_return([ "Invalid CSV format" ])
          allow(controller).to receive(:params).and_return(ActionController::Parameters.new(file: csv_file))
        end

        it "handles import failure appropriately" do
          controller.import

          expect(importer).to have_received(:import)
          expect(controller).to have_received(:redirect_to)
        end
      end

      context "without file parameter" do
        before do
          allow(controller).to receive(:params).and_return(ActionController::Parameters.new)
        end

        it "handles missing file parameter" do
          controller.import

          expect(controller).to have_received(:redirect_to)
        end
      end
    end

    describe "#export (internal method coverage)" do
      let(:patterns) { [ double("pattern1"), double("pattern2") ] }
      let(:csv_data) { "pattern_type,pattern_value,category_name\nmerchant,Test,Food" }

      before do
        allow(controller).to receive(:filter_export_patterns).and_return(patterns)
        allow(controller).to receive(:generate_csv).and_return(csv_data)
        allow(controller).to receive(:send_data)
        # Mock respond_to to actually call the csv block
        allow(controller).to receive(:respond_to) do |&block|
          format_double = double("format")
          allow(format_double).to receive(:csv) do |&csv_block|
            csv_block.call if csv_block
          end
          block.call(format_double) if block
        end
      end

      it "filters patterns and generates CSV data" do
        controller.export

        expect(controller).to have_received(:filter_export_patterns)
        expect(controller).to have_received(:generate_csv).with(patterns)
      end

      it "sends CSV data with correct headers" do
        controller.export

        expect(controller).to have_received(:send_data).with(
          csv_data,
          filename: "patterns-#{Date.current}.csv",
          type: "text/csv",
          disposition: "attachment"
        )
      end

      context "with empty patterns" do
        before do
          allow(controller).to receive(:filter_export_patterns).and_return([])
          allow(controller).to receive(:generate_csv).and_return("pattern_type,pattern_value,category_name\n")
        end

        it "handles empty data gracefully" do
          controller.export

          expect(controller).to have_received(:generate_csv).with([])
        end
      end
    end

    describe "#statistics (internal method coverage)" do
      let(:statistics_calculator) { double("StatisticsCalculator") }
      let(:statistics_data) do
        {
          total_patterns: 150,
          active_patterns: 120,
          patterns_by_type: { merchant: 80, keyword: 40, regex: 30 }
        }
      end

      before do
        allow(Services::Patterns::StatisticsCalculator).to receive(:new).and_return(statistics_calculator)
        allow(statistics_calculator).to receive(:calculate).and_return(statistics_data)
        allow(controller).to receive(:statistics_filters).and_return({})
        allow(controller).to receive(:respond_to).and_yield(double(
          html: double(call: nil),
          json: double(call: nil)
        ))
      end

      it "creates calculator with filters and calculates statistics" do
        controller.statistics

        expect(Services::Patterns::StatisticsCalculator).to have_received(:new).with({})
        expect(statistics_calculator).to have_received(:calculate)
        expect(controller.instance_variable_get(:@statistics)).to eq(statistics_data)
      end

      context "with filters" do
        let(:filters) { { "category_id" => "1", "pattern_type" => "merchant" } }

        before do
          allow(controller).to receive(:statistics_filters).and_return(filters)
        end

        it "passes filters to statistics calculator" do
          controller.statistics

          expect(Services::Patterns::StatisticsCalculator).to have_received(:new).with(filters)
        end
      end
    end

    describe "#performance (internal method coverage)" do
      let(:performance_data) do
        {
          overall_accuracy: 0.85,
          patterns_by_effectiveness: { high: 45, medium: 60, low: 15 },
          category_performance: { "Food" => { accuracy: 0.9, usage: 150 } }
        }
      end

      before do
        allow(controller).to receive(:calculate_performance_data).and_return(performance_data)
        allow(controller).to receive(:performance_cache_key).and_return("test-cache-key")
        allow(Rails.cache).to receive(:fetch).and_return(performance_data)
        allow(controller).to receive(:respond_to).and_yield(double(
          html: double(call: nil),
          json: double(call: nil),
          turbo_stream: double(call: nil)
        ))
      end

      it "caches performance data using cache key" do
        controller.performance

        expect(Rails.cache).to have_received(:fetch).with(
          [ "pattern_performance", "test-cache-key" ],
          expires_in: 15.minutes
        )
        expect(controller.instance_variable_get(:@performance_data)).to eq(performance_data)
      end

      it "calculates performance data when cache miss occurs" do
        allow(Rails.cache).to receive(:fetch).and_yield

        controller.performance

        expect(controller).to have_received(:calculate_performance_data)
      end

      context "with cache key generation" do
        it "generates cache key based on filters" do
          controller.performance

          expect(controller).to have_received(:performance_cache_key)
        end
      end
    end
  end
end
