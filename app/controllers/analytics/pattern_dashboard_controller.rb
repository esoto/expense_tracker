# frozen_string_literal: true

module Analytics
  # Controller for pattern analytics dashboard with secure access controls
  class PatternDashboardController < Admin::BaseController
    # Authorization check for analytics access
    before_action :require_analytics_permission
    before_action :set_filters
    before_action :set_analyzer
    before_action :check_export_rate_limit, only: [ :export ]

    # Main dashboard view
    def index
      @overall_metrics = Rails.cache.fetch(cache_key_for("overall_metrics"), expires_in: 5.minutes) do
        @analyzer.overall_metrics
      end

      @category_performance = Rails.cache.fetch(cache_key_for("category_performance"), expires_in: 5.minutes) do
        @analyzer.category_performance
      end

      @pattern_type_analysis = Rails.cache.fetch(cache_key_for("pattern_type_analysis"), expires_in: 5.minutes) do
        @analyzer.pattern_type_analysis
      end

      @top_patterns = @analyzer.top_patterns(limit: 10)
      @bottom_patterns = @analyzer.bottom_patterns(limit: 10)
      @learning_metrics = @analyzer.learning_metrics
      @recent_activity = @analyzer.recent_activity(limit: 10)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    # Trend chart data endpoint
    def trends
      interval = params[:interval]&.to_sym || :daily
      @trend_data = Rails.cache.fetch(cache_key_for("trends_#{interval}"), expires_in: 10.minutes) do
        @analyzer.trend_analysis(interval: interval)
      end

      respond_to do |format|
        format.json { render json: @trend_data }
        format.turbo_stream
      end
    end

    # Usage heatmap data endpoint
    def heatmap
      @heatmap_data = Rails.cache.fetch(cache_key_for("heatmap"), expires_in: 30.minutes) do
        @analyzer.usage_heatmap
      end

      respond_to do |format|
        format.json { render json: @heatmap_data }
        format.turbo_stream
      end
    end

    # Export dashboard data with rate limiting and audit logging
    def export
      format = validate_export_format(params[:format_type])
      return redirect_to analytics_pattern_dashboard_index_path, alert: "Invalid export format" unless format

      exporter = ::Analytics::DashboardExporter.new(@analyzer, format: format)

      data = exporter.export
      filename = "pattern_analytics_#{Time.current.strftime('%Y%m%d_%H%M%S')}"

      # Audit log the export
      log_analytics_export(format, filename)

      case format
      when :csv
        send_data data,
                  filename: "#{filename}.csv",
                  type: "text/csv",
                  disposition: "attachment"
      when :json
        send_data data,
                  filename: "#{filename}.json",
                  type: "application/json",
                  disposition: "attachment"
      else
        redirect_to analytics_pattern_dashboard_index_path, alert: "Unsupported export format"
      end
    end

    # Real-time updates via Turbo Streams
    def refresh
      component = params[:component]

      case component
      when "overall_metrics"
        @overall_metrics = @analyzer.overall_metrics
        render turbo_stream: turbo_stream.replace(
          "overall_metrics",
          partial: "analytics/pattern_dashboard/overall_metrics",
          locals: { overall_metrics: @overall_metrics }
        )
      when "category_performance"
        @category_performance = @analyzer.category_performance
        render turbo_stream: turbo_stream.replace(
          "category_performance",
          partial: "analytics/pattern_dashboard/category_performance",
          locals: { category_performance: @category_performance }
        )
      when "recent_activity"
        @recent_activity = @analyzer.recent_activity(limit: 10)
        render turbo_stream: turbo_stream.replace(
          "recent_activity",
          partial: "analytics/pattern_dashboard/recent_activity",
          locals: { recent_activity: @recent_activity }
        )
      else
        head :unprocessable_content
      end
    end

    private

    def set_filters
      @time_range = parse_time_range
      @category_id = params[:category_id]
      @pattern_type = params[:pattern_type]
    end

    def set_analyzer
      @analyzer = ::Services::Analytics::PatternPerformanceAnalyzer.new(
        time_range: @time_range,
        category_id: @category_id,
        pattern_type: @pattern_type
      )
    end

    def parse_time_range
      case params[:time_period]
      when "today"
        Time.current.beginning_of_day..Time.current
      when "week"
        1.week.ago..Time.current
      when "month"
        1.month.ago..Time.current
      when "quarter"
        3.months.ago..Time.current
      when "year"
        1.year.ago..Time.current
      when "custom"
        parse_custom_date_range
      else
        30.days.ago..Time.current
      end
    rescue ArgumentError, TypeError => e
      Rails.logger.error "Date parsing error: #{e.message}"
      # Return default range on parsing error
      30.days.ago..Time.current
    end

    def cache_key_for(component)
      [
        "pattern_analytics",
        component,
        @time_range.first.to_time.to_i,
        @time_range.last.to_time.to_i,
        @category_id,
        @pattern_type,
        cache_version_key
      ].compact.join("/")
    end

    def cache_version_key
      # Composite cache version based on relevant models
      [
        CategorizationPattern.maximum(:updated_at)&.to_i,
        PatternFeedback.maximum(:updated_at)&.to_i,
        PatternLearningEvent.maximum(:updated_at)&.to_i
      ].compact.join("-")
    end

    def require_analytics_permission
      unless current_admin_user.can_access_statistics?
        render_forbidden("You don't have permission to access analytics.")
      end
    end

    def check_export_rate_limit
      # Check if user has exceeded export rate limit (5 exports per hour)
      cache_key = "export_rate_limit:#{current_admin_user.id}"
      count = Rails.cache.increment(cache_key, 1, expires_in: 1.hour)

      if count > 5
        log_rate_limit_exceeded("export")
        render_forbidden("Export rate limit exceeded. Please try again later.")
      end
    end

    def validate_export_format(format_param)
      return :csv if format_param.blank?

      allowed_formats = [ :csv, :json ]
      format = format_param.to_sym
      allowed_formats.include?(format) ? format : nil
    end

    def parse_custom_date_range
      begin
        start_date = if params[:start_date].present?
                       Date.parse(params[:start_date])
        else
                       30.days.ago.to_date
        end

        end_date = if params[:end_date].present?
                     Date.parse(params[:end_date])
        else
                     Date.current
        end

        # Validate date range
        if start_date > end_date
          Rails.logger.warn "Invalid date range: start_date > end_date for user #{current_admin_user.id}"
          return 30.days.ago..Time.current
        end

        max_range_date = ::Services::Analytics::PatternPerformanceAnalyzer::MAX_DATE_RANGE_YEARS.years.ago.to_date
        if start_date < max_range_date
          Rails.logger.warn "Date range too large, limiting to #{::Services::Analytics::PatternPerformanceAnalyzer::MAX_DATE_RANGE_YEARS} years"
          start_date = max_range_date
        end

        start_date..end_date
      rescue Date::Error, ArgumentError => e
        Rails.logger.error "Date parsing error in analytics dashboard: #{e.message}"
        flash.now[:alert] = "Invalid date format. Using default date range."
        30.days.ago..Time.current
      end
    end

    def log_analytics_export(format, filename)
      log_admin_action(
        "analytics.export",
        {
          format: format,
          filename: filename,
          time_range: @time_range.to_s,
          category_id: @category_id,
          pattern_type: @pattern_type,
          records_exported: @analyzer.overall_metrics[:total_patterns]
        }
      )
    end

    def log_rate_limit_exceeded(action)
      log_admin_action(
        "rate_limit.exceeded",
        {
          action: action,
          controller: controller_name,
          user_id: current_admin_user.id
        }
      )
    end
  end
end
