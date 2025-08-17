# frozen_string_literal: true

# DashboardExpenseFilterService provides optimized filtering for dashboard expense widget
# Extends ExpenseFilterService with dashboard-specific optimizations and context
# Achieves <50ms query performance for dashboard recent expenses section
class DashboardExpenseFilterService < ExpenseFilterService
  # Constants for dashboard context
  DEFAULT_DASHBOARD_LIMIT = 10
  MAX_DASHBOARD_LIMIT = 50
  DASHBOARD_CACHE_TTL = 2.minutes

  # Dashboard-specific result class extending base Result
  class DashboardResult < ExpenseFilterService::Result
    attr_reader :summary_stats, :quick_filters, :view_mode

    def initialize(expenses:, total_count:, metadata:, performance_metrics: {}, 
                   summary_stats: nil, quick_filters: nil, view_mode: nil)
      super(expenses: expenses, total_count: total_count, 
            metadata: metadata, performance_metrics: performance_metrics)
      @summary_stats = summary_stats
      @quick_filters = quick_filters
      @view_mode = view_mode || "compact"
    end

    def dashboard_cache_key
      [
        "dashboard_expense_filter",
        metadata[:filters_hash],
        view_mode,
        metadata[:page]
      ].join("/")
    end

    def has_filters?
      metadata[:filters_applied] > 0
    end

    def to_json(*args)
      super_json = super
      parsed = JSON.parse(super_json)
      parsed["meta"] ||= {}
      parsed["meta"]["summary_stats"] = summary_stats if summary_stats
      parsed["meta"]["quick_filters"] = quick_filters if quick_filters
      parsed["meta"]["view_mode"] = view_mode
      parsed.to_json(*args)
    end
  end

  def initialize(params = {})
    # Extract dashboard-specific params before passing to parent
    @view_mode = params.delete(:view_mode) || "compact"
    @include_summary = params.delete(:include_summary) != false
    @include_quick_filters = params.delete(:include_quick_filters) != false
    @dashboard_context = true
    
    # Set dashboard defaults and call parent
    dashboard_params = normalize_dashboard_params(params)
    super(dashboard_params)
  end

  def call
    return cached_dashboard_result if dashboard_cache_enabled? && cached_dashboard_result.present?

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    # Track query execution with dashboard context
    query_counter = 0
    query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      query_counter += 1 unless payload[:cached] || payload[:name] == "SCHEMA"
    end

    # Build optimized dashboard scope
    scope = build_dashboard_scope
    scope = apply_filters(scope)
    scope = apply_dashboard_sorting(scope)
    expenses, pagination_meta = apply_dashboard_pagination(scope)

    # Calculate dashboard-specific metrics
    summary_stats = calculate_summary_stats(scope) if @include_summary
    quick_filters = generate_quick_filters(scope) if @include_quick_filters

    # Calculate performance metrics
    query_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    # Unsubscribe from notifications
    ActiveSupport::Notifications.unsubscribe(query_subscriber) if query_subscriber
    queries_executed = query_counter

    result = build_dashboard_result(
      expenses, 
      pagination_meta, 
      query_time, 
      queries_executed,
      summary_stats,
      quick_filters
    )
    
    cache_dashboard_result(result) if dashboard_cache_enabled?
    
    # Log performance for dashboard context
    log_dashboard_performance(result) if query_time > 0.05

    result
  rescue StandardError => e
    Rails.logger.error "DashboardExpenseFilterService error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    DashboardResult.new(
      expenses: [],
      total_count: 0,
      metadata: { error: e.message },
      performance_metrics: { error: true },
      view_mode: @view_mode
    )
  end

  private

  def normalize_dashboard_params(params)
    normalized = params.to_h.deep_symbolize_keys
    
    # Set dashboard-specific defaults
    normalized[:per_page] ||= DEFAULT_DASHBOARD_LIMIT
    normalized[:page] ||= 1
    
    # Handle period-based filtering from dashboard
    if normalized[:period].present? && !normalized[:start_date] && !normalized[:end_date]
      dates = calculate_period_dates(normalized[:period])
      normalized[:start_date] = dates[:start]
      normalized[:end_date] = dates[:end]
    end
    
    # Ensure we don't exceed dashboard limits
    normalized[:per_page] = [normalized[:per_page].to_i, MAX_DASHBOARD_LIMIT].min
    
    normalized
  end

  def build_dashboard_scope
    # Use optimized scope with dashboard-specific eager loading
    Expense
      .for_list_display
      .includes(:category, :email_account, :ml_suggested_category)
      .where(email_account_id: account_ids)
  end

  def apply_dashboard_sorting(scope)
    # Dashboard always shows most recent first by default
    safe_column = %w[transaction_date amount merchant_name created_at].include?(sort_by) ? sort_by : "transaction_date"
    safe_direction = %w[asc desc].include?(sort_direction) ? sort_direction : "desc"
    
    # Use compound sorting for better UX
    primary_order = { safe_column.to_sym => safe_direction.to_sym }
    secondary_order = safe_column == "transaction_date" ? { created_at: :desc } : { transaction_date: :desc }
    
    scope.order(primary_order).order(secondary_order).order(id: :desc)
  end

  def apply_dashboard_pagination(scope)
    # Dashboard uses simple offset pagination
    expenses = scope.limit(per_page).offset((page - 1) * per_page)
    
    # Get total count efficiently
    total = if scope.respond_to?(:total_count)
              scope.total_count
            else
              # Use cache for count queries
              cache_key = "dashboard_expense_count/#{generate_filters_hash}"
              Rails.cache.fetch(cache_key, expires_in: DASHBOARD_CACHE_TTL) do
                scope.except(:limit, :offset, :order).count
              end
            end
    
    pagination_meta = {
      total_count: total,
      page: page,
      has_more: total > (page * per_page)
    }
    
    [expenses, pagination_meta]
  end

  def calculate_summary_stats(scope)
    # Use single query for all aggregates
    stats = scope
      .except(:limit, :offset, :order)
      .pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(amount)"),
        Arel.sql("AVG(amount)"),
        Arel.sql("MIN(amount)"),
        Arel.sql("MAX(amount)"),
        Arel.sql("COUNT(DISTINCT merchant_normalized)"),
        Arel.sql("COUNT(DISTINCT category_id)")
      )
    
    {
      total_count: stats[0] || 0,
      total_amount: (stats[1] || 0).to_f,
      average_amount: (stats[2] || 0).to_f,
      min_amount: (stats[3] || 0).to_f,
      max_amount: (stats[4] || 0).to_f,
      unique_merchants: stats[5] || 0,
      unique_categories: stats[6] || 0
    }
  end

  def generate_quick_filters(scope)
    # Generate available quick filter options based on current data
    base_scope = scope.except(:limit, :offset, :order)
    
    {
      categories: base_scope
        .joins(:category)
        .group("categories.id", "categories.name", "categories.color")
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(5)
        .pluck("categories.id", "categories.name", "categories.color", Arel.sql("COUNT(*)"))
        .map { |id, name, color, count| 
          { id: id, name: name, color: color, count: count }
        },
      
      statuses: base_scope
        .group(:status)
        .count
        .sort_by { |_, count| -count }
        .map { |status, count| 
          { status: status, count: count, label: status.humanize }
        },
      
      recent_periods: [
        { period: "today", label: "Hoy", count: count_for_period(base_scope, "today") },
        { period: "week", label: "Esta Semana", count: count_for_period(base_scope, "week") },
        { period: "month", label: "Este Mes", count: count_for_period(base_scope, "month") }
      ].select { |p| p[:count] > 0 }
    }
  end

  def count_for_period(scope, period)
    dates = calculate_period_dates(period)
    return 0 unless dates[:start] && dates[:end]
    
    scope.where(transaction_date: dates[:start]..dates[:end]).count
  end

  def calculate_period_dates(period)
    today = Date.current
    case period.to_s
    when "today", "day"
      { start: today, end: today }
    when "week"
      { start: today.beginning_of_week, end: today.end_of_week }
    when "month"
      { start: today.beginning_of_month, end: today.end_of_month }
    when "year"
      { start: today.beginning_of_year, end: today.end_of_year }
    when "last_7_days"
      { start: 7.days.ago.to_date, end: today }
    when "last_30_days"
      { start: 30.days.ago.to_date, end: today }
    else
      {}
    end
  end

  def build_dashboard_result(expenses, pagination_meta, query_time, queries_executed, summary_stats, quick_filters)
    DashboardResult.new(
      expenses: expenses,
      total_count: pagination_meta[:total_count],
      metadata: {
        page: pagination_meta[:page],
        per_page: per_page,
        has_more: pagination_meta[:has_more],
        filters_applied: count_active_filters,
        filters_hash: generate_filters_hash,
        sort: { by: sort_by, direction: sort_direction },
        dashboard_context: true
      },
      performance_metrics: {
        query_time_ms: (query_time * 1000).round(2),
        cached: false,
        index_used: check_index_usage(expenses),
        queries_executed: queries_executed,
        rows_examined: expenses.count,
        dashboard_optimized: true
      },
      summary_stats: summary_stats,
      quick_filters: quick_filters,
      view_mode: @view_mode
    )
  end

  def dashboard_cache_enabled?
    cache_enabled? && @dashboard_context
  end

  def cached_dashboard_result
    @cached_dashboard_result ||= Rails.cache.read(dashboard_cache_key)
  end

  def cache_dashboard_result(result)
    Rails.cache.write(dashboard_cache_key, result, expires_in: DASHBOARD_CACHE_TTL)
  end

  def dashboard_cache_key
    ["dashboard_expense_filter", generate_filters_hash, @view_mode, page, per_page].join("/")
  end

  def log_dashboard_performance(result)
    Rails.logger.info({
      service: "DashboardExpenseFilterService",
      query_time_ms: result.performance_metrics[:query_time_ms],
      rows_examined: result.performance_metrics[:rows_examined],
      filters_applied: result.metadata[:filters_applied],
      view_mode: result.view_mode,
      has_summary: result.summary_stats.present?,
      has_quick_filters: result.quick_filters.present?,
      index_used: result.performance_metrics[:index_used]
    }.to_json)

    # Send metrics to monitoring service if configured
    if defined?(StatsD)
      StatsD.timing("dashboard_expense_filter.query_time", result.performance_metrics[:query_time_ms])
      StatsD.gauge("dashboard_expense_filter.rows_examined", result.performance_metrics[:rows_examined])
      StatsD.increment("dashboard_expense_filter.requests")
    end
  end
end