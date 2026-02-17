# frozen_string_literal: true

require "csv"
require "ostruct"

module Admin
  # Controller for managing categorization patterns through admin UI
  # Implements comprehensive security, performance optimization, and accessibility
  class PatternsController < BaseController
    # Security filters
    before_action :require_pattern_management_permission, except: [ :index, :show ]
    before_action :require_pattern_edit_permission, only: [ :edit, :update ]
    before_action :require_pattern_delete_permission, only: [ :destroy ]
    before_action :require_import_permission, only: [ :import ]
    before_action :require_statistics_permission, only: [ :statistics, :performance ]

    # Rate limiting for resource-intensive operations
    before_action :check_rate_limit_for_testing, only: [ :test_pattern, :test_single ]
    before_action :check_rate_limit_for_import, only: [ :import ]

    # Resource loading
    before_action :set_pattern, only: [ :show, :edit, :update, :destroy, :toggle_active, :test_single ]
    before_action :load_categories, only: [ :new, :edit, :create, :update, :test ]

    # Response caching
    after_action :set_cache_headers, only: [ :index, :show, :statistics, :performance ]

    # GET /admin/patterns
    def index
      @patterns = build_patterns_scope
      load_statistics

      respond_to do |format|
        format.html
        format.turbo_stream
        format.json { render_patterns_json }
      end
    end

    # GET /admin/patterns/:id
    def show
      feedback_page = [ (params[:feedback_page] || 1).to_i, 1 ].max
      @pattern_feedbacks = @pattern.pattern_feedbacks
                                   .includes(:expense)
                                   .order(created_at: :desc)
                                   .limit(10).offset((feedback_page - 1) * 10)

      @performance_metrics = Rails.cache.fetch(
        [ "pattern_metrics", @pattern.id, @pattern.updated_at ],
        expires_in: 1.hour
      ) do
        calculate_performance_metrics(@pattern)
      end

      respond_to do |format|
        format.html
        format.json { render json: pattern_with_details }
      end
    end

    # GET /admin/patterns/new
    def new
      @pattern = CategorizationPattern.new(
        confidence_weight: CategorizationPattern::DEFAULT_CONFIDENCE_WEIGHT,
        active: true,
        user_created: true
      )
    end

    # GET /admin/patterns/:id/edit
    def edit
      # @pattern is already loaded by set_pattern before_action
      # Load categories for the form dropdown
    end

    # POST /admin/patterns
    def create
      @pattern = CategorizationPattern.new(pattern_params)
      @pattern.user_created = true
      @pattern.usage_count = 0
      @pattern.success_count = 0
      @pattern.success_rate = 0.0

      if @pattern.save
        log_admin_action("pattern_created", pattern_id: @pattern.id)
        redirect_to admin_pattern_path(@pattern),
                    notice: "Pattern was successfully created.",
                    status: :see_other
      else
        render :new, status: :unprocessable_content
      end
    end

    # PATCH/PUT /admin/patterns/:id
    def update
      if @pattern.update(pattern_params)
        log_admin_action("pattern_updated", pattern_id: @pattern.id)
        redirect_to admin_pattern_path(@pattern),
                    notice: "Pattern was successfully updated.",
                    status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    # DELETE /admin/patterns/:id
    def destroy
      @pattern.destroy
      log_admin_action("pattern_deleted", pattern_id: @pattern.id)
      redirect_to admin_patterns_path,
                  notice: "Pattern was successfully deleted.",
                  status: :see_other
    end

    # POST /admin/patterns/:id/toggle_active
    def toggle_active
      @pattern.update!(active: !@pattern.active)
      log_admin_action("pattern_toggled", pattern_id: @pattern.id, active: @pattern.active)

      respond_to do |format|
        format.html { redirect_to admin_patterns_path, status: :see_other }
        format.turbo_stream { render_toggle_response }
      end
    end

    # GET /admin/patterns/test
    def test
      @test_expense = build_test_expense
      @patterns = CategorizationPattern.active.includes(:category)
    end

    # POST /admin/patterns/test_pattern
    def test_pattern
      tester = Services::Patterns::PatternTester.new(test_pattern_params)

      if tester.test
        @matching_patterns = tester.categories_with_confidence
        @test_expense = tester.test_expense

        respond_to do |format|
          format.turbo_stream { render_test_results }
          format.json { render json: { matches: @matching_patterns } }
        end
      else
        respond_to do |format|
          format.turbo_stream { render_test_error(tester.errors.full_messages) }
          format.json { render json: { errors: tester.errors }, status: :unprocessable_content }
        end
      end
    end

    # POST /admin/patterns/:id/test_single
    def test_single
      test_text = sanitize_test_input(params[:test_text])

      if test_text.present?
        @matches = @pattern.matches?(test_text)

        respond_to do |format|
          format.turbo_stream { render_single_test_result }
          format.json { render json: { matches: @matches, pattern_id: @pattern.id } }
        end
      else
        respond_to do |format|
          format.turbo_stream { render_test_error([ "Test text is required" ]) }
          format.json { render json: { error: "Test text is required" }, status: :unprocessable_content }
        end
      end
    end

    # POST /admin/patterns/import
    def import
      importer = Services::Patterns::CsvImporter.new(
        file: params[:file],
        user: current_admin_user,
        dry_run: params[:dry_run] == "true"
      )

      if importer.import
        log_admin_action("patterns_imported", summary: importer.summary)
        redirect_to admin_patterns_path,
                    notice: import_success_message(importer),
                    status: :see_other
      else
        redirect_to admin_patterns_path,
                    alert: import_error_message(importer),
                    status: :see_other
      end
    end

    # GET /admin/patterns/export
    def export
      patterns = filter_export_patterns

      respond_to do |format|
        format.csv do
          send_data generate_csv(patterns),
                    filename: "patterns-#{Date.current}.csv",
                    type: "text/csv",
                    disposition: "attachment"
        end
      end
    end

    # GET /admin/patterns/statistics
    def statistics
      calculator = Services::Patterns::StatisticsCalculator.new(statistics_filters)
      @statistics = calculator.calculate

      respond_to do |format|
        format.html
        format.json { render json: @statistics }
      end
    end

    # GET /admin/patterns/performance
    def performance
      @performance_data = Rails.cache.fetch(
        [ "pattern_performance", performance_cache_key ],
        expires_in: 15.minutes
      ) do
        calculate_performance_data
      end

      respond_to do |format|
        format.html
        format.json { render json: @performance_data }
        format.turbo_stream
      end
    end

    private

    def set_pattern
      @pattern = CategorizationPattern.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_patterns_path, alert: "Pattern not found"
    end

    def load_categories
      @categories = Category.order(:name)
    end

    def load_statistics
      @total_patterns = @patterns.except(:limit, :offset).count
      @active_patterns = @patterns.except(:limit, :offset).active.count

      stats = CategorizationPattern.where("usage_count > 0")
                                    .pluck("SUM(success_count)", "SUM(usage_count)")
                                    .first

      @average_success_rate = if stats && stats[1].to_i > 0
                                ((stats[0].to_f / stats[1].to_i) * 100).round(2)
      else
                                0
      end

      @total_usage = @patterns.except(:limit, :offset).sum(:usage_count)
    end

    def pattern_params
      params.require(:categorization_pattern).permit(
        :pattern_type,
        :pattern_value,
        :category_id,
        :confidence_weight,
        :active,
        metadata: {}
      ).tap do |p|
        p[:pattern_value] = sanitize_pattern_value(p[:pattern_value], p[:pattern_type])
      end
    end

    def test_pattern_params
      params.permit(:description, :merchant_name, :amount, :transaction_date)
    end

    def sanitize_pattern_value(value, pattern_type)
      return nil if value.blank?

      case pattern_type
      when "regex"
        validate_safe_regex(value) ? value : nil
      else
        ActionController::Base.helpers.sanitize(value, tags: [])
          .strip
          .truncate(255)
      end
    end

    def sanitize_test_input(value)
      return nil if value.blank?

      ActionController::Base.helpers.sanitize(value, tags: [])
        .strip
        .truncate(500)
    end

    def validate_safe_regex(pattern)
      return false if pattern.blank?

      dangerous = [
        /\([^)]*[+*]\)[+*]/,
        /\[[^\]]*[+*]\][+*]/,
        /(\w+[+*])+[+*]/,
        /\(.+[+*].+\)[+*]/
      ]

      return false if dangerous.any? { |d| pattern.match?(d) }

      Timeout.timeout(0.5) { Regexp.new(pattern) }
      true
    rescue RegexpError, Timeout::Error
      false
    end

    def build_patterns_scope
      scope = CategorizationPattern.includes(:category)
      scope = apply_filters(scope)
      scope = apply_search(scope) if params[:search].present?
      scope = apply_sorting(scope)
      page = [ (params[:page] || 1).to_i, 1 ].max
      scope.limit(20).offset((page - 1) * 20)
    end

    def apply_filters(scope)
      if params[:filter_type].present?
        scope = scope.by_type(params[:filter_type])
      end

      if params[:filter_category].present?
        scope = scope.where(category_id: params[:filter_category])
      end

      if params[:filter_status].present?
        scope = apply_status_filter(scope, params[:filter_status])
      end

      scope
    end

    def apply_status_filter(scope, status)
      case status
      when "active" then scope.active
      when "inactive" then scope.inactive
      when "user_created" then scope.user_created
      when "system_created" then scope.system_created
      when "high_confidence" then scope.high_confidence
      when "successful" then scope.successful
      when "frequently_used" then scope.frequently_used
      else scope
      end
    end

    def apply_search(scope)
      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%"
      scope.joins(:category)
           .where(
             "pattern_value ILIKE ? OR categories.name ILIKE ?",
             search_term, search_term
           )
    end

    def apply_sorting(scope)
      case params[:sort]
      when "type" then scope.order(:pattern_type)
      when "value" then scope.order(:pattern_value)
      when "category" then scope.joins(:category).order("categories.name")
      when "usage" then scope.order(usage_count: :desc)
      when "success" then scope.order(success_rate: :desc, usage_count: :desc)
      when "confidence" then scope.order(confidence_weight: :desc)
      when "created" then scope.order(created_at: :desc)
      else scope.ordered_by_success
      end
    end

    def filter_export_patterns
      patterns = CategorizationPattern.includes(:category)

      if params[:export_active_only] == "true"
        patterns = patterns.active
      end

      if params[:export_category_id].present?
        patterns = patterns.where(category_id: params[:export_category_id])
      end

      patterns.limit(5000)
    end

    def generate_csv(patterns)
      CSV.generate(headers: true) do |csv|
        csv << csv_headers
        patterns.find_each do |pattern|
          csv << csv_row(pattern)
        end
      end
    end

    def csv_headers
      [ "pattern_type", "pattern_value", "category_id", "category_name",
       "confidence_weight", "active", "usage_count", "success_count",
       "success_rate", "created_at" ]
    end

    def csv_row(pattern)
      [
        pattern.pattern_type,
        pattern.pattern_value,
        pattern.category_id,
        pattern.category.name,
        pattern.confidence_weight,
        pattern.active,
        pattern.usage_count,
        pattern.success_count,
        pattern.success_rate,
        pattern.created_at
      ]
    end

    def calculate_performance_metrics(pattern)
      {
        total_uses: pattern.usage_count,
        successful_uses: pattern.success_count,
        success_rate: (pattern.success_rate * 100).round(2),
        confidence: pattern.effective_confidence,
        last_used: pattern.pattern_feedbacks.maximum(:created_at),
        average_daily_uses: calculate_average_daily_uses(pattern),
        trend: calculate_trend(pattern)
      }
    end

    def calculate_average_daily_uses(pattern)
      return 0 if pattern.created_at > 30.days.ago

      days_active = (Date.current - pattern.created_at.to_date).to_i
      return 0 if days_active.zero?

      (pattern.usage_count.to_f / days_active).round(2)
    end

    def calculate_trend(pattern)
      recent_count = pattern.pattern_feedbacks
                           .where(created_at: 7.days.ago..)
                           .count

      older_count = pattern.pattern_feedbacks
                          .where(created_at: 14.days.ago..7.days.ago)
                          .count

      if recent_count > older_count
        "increasing"
      elsif recent_count < older_count
        "decreasing"
      else
        "stable"
      end
    end

    def calculate_performance_data
      {
        overall_accuracy: calculate_overall_accuracy,
        patterns_by_effectiveness: patterns_by_effectiveness,
        category_accuracy: category_accuracy_rates,
        time_series_performance: time_series_performance_data,
        low_performers: low_performing_patterns,
        high_performers: high_performing_patterns
      }
    end

    def calculate_overall_accuracy
      stats = CategorizationPattern
        .where("usage_count > 0")
        .pluck("SUM(success_count)", "SUM(usage_count)")
        .first

      return 0 unless stats && stats[1].to_i > 0

      ((stats[0].to_f / stats[1]) * 100).round(2)
    end

    def patterns_by_effectiveness
      CategorizationPattern
        .group(:pattern_type)
        .where("usage_count > 0")
        .pluck(
          :pattern_type,
          "AVG(success_rate) as avg_rate",
          "SUM(usage_count) as total"
        )
        .map do |type, rate, total|
          {
            type: type,
            average_success_rate: (rate * 100).round(2),
            total_usage: total
          }
        end
        .sort_by { |r| -r[:average_success_rate] }
    end

    def category_accuracy_rates
      Category
        .joins(:categorization_patterns)
        .where("categorization_patterns.usage_count > 0")
        .group("categories.id, categories.name")
        .pluck(
          "categories.name",
          "AVG(categorization_patterns.success_rate)",
          "SUM(categorization_patterns.usage_count)"
        )
        .map do |name, rate, usage|
          {
            name: name,
            accuracy: (rate * 100).round(2),
            total_usage: usage
          }
        end
        .sort_by { |c| -c[:accuracy] }
        .first(20)
    end

    def time_series_performance_data
      days = 30
      end_date = Date.current
      start_date = end_date - days.days

      daily_stats = PatternFeedback
        .where(created_at: start_date..end_date)
        .group("DATE(created_at)", :was_correct)
        .count

      (start_date..end_date).map do |date|
        correct = daily_stats[[ date, true ]] || 0
        incorrect = daily_stats[[ date, false ]] || 0
        total = correct + incorrect

        {
          date: date.to_s,
          correct: correct,
          incorrect: incorrect,
          accuracy: total > 0 ? (correct.to_f / total * 100).round(2) : 0
        }
      end
    end

    def low_performing_patterns
      CategorizationPattern
        .active
        .where("usage_count >= 10 AND success_rate < 0.5")
        .includes(:category)
        .order(success_rate: :asc)
        .limit(10)
        .map { |p| pattern_summary(p) }
    end

    def high_performing_patterns
      CategorizationPattern
        .active
        .successful
        .frequently_used
        .includes(:category)
        .order(success_rate: :desc, usage_count: :desc)
        .limit(10)
        .map { |p| pattern_summary(p) }
    end

    def pattern_summary(pattern)
      {
        id: pattern.id,
        type: pattern.pattern_type,
        value: pattern.pattern_value,
        category: pattern.category.name,
        usage: pattern.usage_count,
        success_rate: (pattern.success_rate * 100).round(2)
      }
    end

    def pattern_with_details
      {
        pattern: @pattern.as_json(include: :category),
        performance: @performance_metrics,
        recent_feedbacks: @pattern.pattern_feedbacks
                                  .recent
                                  .limit(5)
                                  .as_json(include: :expense)
      }
    end

    def build_test_expense
      OpenStruct.new(
        description: params[:description],
        merchant_name: params[:merchant_name],
        amount: params[:amount]&.to_f,
        transaction_date: params[:transaction_date]&.to_datetime || DateTime.current
      )
    end

    def render_patterns_json
      page = [ (params[:page] || 1).to_i, 1 ].max
      per_page = @patterns.respond_to?(:limit_value) ? (@patterns.limit_value || 20) : 20
      total_patterns_count = @total_patterns || 0
      total_pages = total_patterns_count.positive? ? (total_patterns_count.to_f / per_page).ceil : 1

      render json: {
        patterns: @patterns.as_json(include: :category),
        meta: {
          total: @total_patterns,
          active: @active_patterns,
          average_success_rate: @average_success_rate,
          total_usage: @total_usage,
          current_page: page,
          total_pages: total_pages
        }
      }
    end

    def render_toggle_response
      render turbo_stream: [
        turbo_stream.replace(
          dom_id(@pattern, :row),
          partial: "admin/patterns/pattern_row",
          locals: { pattern: @pattern }
        ),
        turbo_stream.replace(
          "flash",
          partial: "shared/flash",
          locals: {
            notice: @pattern.active? ? "Pattern activated" : "Pattern deactivated"
          }
        )
      ]
    end

    def render_test_results
      render turbo_stream: turbo_stream.replace(
        "test_results",
        partial: "admin/patterns/test_results",
        locals: {
          matching_patterns: @matching_patterns,
          test_expense: @test_expense
        }
      )
    end

    def render_single_test_result
      render turbo_stream: turbo_stream.replace(
        "single_test_result",
        partial: "admin/patterns/single_test_result",
        locals: {
          pattern: @pattern,
          matches: @matches,
          test_text: params[:test_text]
        }
      )
    end

    def render_test_error(errors)
      render turbo_stream: turbo_stream.replace(
        "test_results",
        partial: "shared/errors",
        locals: { errors: errors }
      )
    end

    def import_success_message(importer)
      summary = importer.summary
      "Successfully imported #{summary[:imported]} patterns" +
        (summary[:skipped] > 0 ? " (#{summary[:skipped]} skipped)" : "")
    end

    def import_error_message(importer)
      "Import failed: #{importer.import_errors.join('; ')}"
    end

    def statistics_filters
      params.permit(:category_id, :pattern_type, :active).to_h
    end

    def performance_cache_key
      [
        params[:filter_type],
        params[:filter_category],
        params[:filter_status],
        params[:date_range]
      ].compact.join("-")
    end

    def check_rate_limit_for_testing
      rate_limit_key = "pattern_test:#{current_admin_user.id}"

      if Rails.cache.increment(rate_limit_key, 1, expires_in: 1.minute) > 30
        render_rate_limit_error
      end
    end

    def check_rate_limit_for_import
      rate_limit_key = "pattern_import:#{current_admin_user.id}"

      if Rails.cache.increment(rate_limit_key, 1, expires_in: 1.hour) > 5
        render_rate_limit_error
      end
    end

    def render_rate_limit_error
      respond_to do |format|
        format.html { redirect_back(fallback_location: admin_patterns_path, alert: "Rate limit exceeded. Please try again later.") }
        format.json { render json: { error: "Rate limit exceeded" }, status: :too_many_requests }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { alert: "Rate limit exceeded" }) }
      end
    end

    def set_cache_headers
      if request.get? && response.successful?
        expires_in 5.minutes, public: false
      end
    end
  end
end
