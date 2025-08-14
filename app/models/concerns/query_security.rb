# frozen_string_literal: true

# QuerySecurity provides security features for database queries
# Including rate limiting, query cost analysis, and injection prevention
module QuerySecurity
  extend ActiveSupport::Concern
  
  # Query cost thresholds
  MAX_QUERY_COST = 10000
  MAX_ROWS_PER_REQUEST = 1000
  RATE_LIMIT_WINDOW = 1.minute
  MAX_REQUESTS_PER_WINDOW = 100
  
  included do
    # Track query metrics
    class_attribute :query_metrics, default: {}
    
    # Add query security validations
    before_save :validate_query_security, if: :query_security_enabled?
    
    # Add rate limiting to query-heavy scopes
    scope :with_rate_limit, ->(identifier = nil) {
      if rate_limit_exceeded?(identifier)
        raise ActiveRecord::QueryAborted, "Rate limit exceeded. Please try again later."
      end
      increment_rate_limit(identifier)
      current_scope || all
    }
    
    # Add query cost analysis
    scope :with_cost_analysis, -> {
      query = current_scope || all
      cost = estimate_query_cost(query)
      
      if cost > MAX_QUERY_COST
        Rails.logger.warn "High cost query detected: #{cost}"
        raise ActiveRecord::QueryAborted, "Query too expensive. Please narrow your search criteria."
      end
      
      query
    }
  end
  
  class_methods do
    # Rate limiting implementation
    def rate_limit_exceeded?(identifier = nil)
      return false unless rate_limiting_enabled?
      
      key = rate_limit_key(identifier)
      current_count = rate_limit_store.get(key).to_i
      current_count >= MAX_REQUESTS_PER_WINDOW
    end
    
    def increment_rate_limit(identifier = nil)
      return unless rate_limiting_enabled?
      
      key = rate_limit_key(identifier)
      store = rate_limit_store
      
      if store.exists?(key)
        store.incr(key)
      else
        store.setex(key, RATE_LIMIT_WINDOW.to_i, 1)
      end
    end
    
    def rate_limit_key(identifier = nil)
      identifier ||= request_identifier
      "query_rate_limit:#{name}:#{identifier}"
    end
    
    def request_identifier
      # Get identifier from request context
      if defined?(RequestStore) && RequestStore.store[:request_id]
        RequestStore.store[:request_id]
      elsif Thread.current[:request_id]
        Thread.current[:request_id]
      else
        "unknown"
      end
    end
    
    def rate_limit_store
      # Use Redis if available, otherwise in-memory store
      if defined?(Rails.application.config.redis_metrics)
        Rails.application.config.redis_metrics
      else
        @rate_limit_store ||= MemoryRateLimitStore.new
      end
    end
    
    def rate_limiting_enabled?
      Rails.application.config.respond_to?(:enable_query_rate_limiting) &&
        Rails.application.config.enable_query_rate_limiting
    end
    
    # Query cost estimation
    def estimate_query_cost(scope)
      return 0 unless scope.respond_to?(:to_sql)
      
      begin
        # Use EXPLAIN to get query cost
        explain_result = connection.execute("EXPLAIN (FORMAT JSON) #{scope.to_sql}")
        plan = JSON.parse(explain_result.first["QUERY PLAN"]).first
        
        # Extract total cost from plan
        total_cost = plan.dig("Plan", "Total Cost") || 0
        rows = plan.dig("Plan", "Plan Rows") || 0
        
        # Calculate weighted cost
        (total_cost + (rows * 0.1)).to_i
      rescue StandardError => e
        Rails.logger.debug "Could not estimate query cost: #{e.message}"
        0
      end
    end
    
    # SQL injection prevention helpers
    def sanitize_like_query(query)
      return "" if query.blank?
      
      # Escape special characters for LIKE queries
      query.gsub(/[%_\\]/) { |char| "\\#{char}" }
    end
    
    def validate_cursor(cursor)
      return nil if cursor.blank?
      
      # Validate cursor format (base64 encoded JSON)
      begin
        decoded = Base64.strict_decode64(cursor)
        JSON.parse(decoded)
        cursor
      rescue StandardError
        raise ArgumentError, "Invalid cursor format"
      end
    end
    
    def validate_sort_column(column, allowed_columns)
      return "created_at" unless column.present?
      
      # Whitelist approach for column names
      allowed = allowed_columns.map(&:to_s)
      column.to_s.in?(allowed) ? column.to_s : "created_at"
    end
    
    def validate_sort_direction(direction)
      %w[asc desc].include?(direction.to_s.downcase) ? direction.to_s.downcase : "desc"
    end
    
    # Pagination security
    def validate_page_size(size, max_size = 100)
      size = size.to_i
      return 50 if size <= 0
      [size, max_size].min
    end
    
    def validate_page_number(page)
      page = page.to_i
      page > 0 ? page : 1
    end
    
    # Query complexity analysis
    def analyze_query_complexity(scope)
      analysis = {
        joins: count_joins(scope),
        conditions: count_conditions(scope),
        aggregations: count_aggregations(scope),
        subqueries: count_subqueries(scope)
      }
      
      complexity_score = calculate_complexity_score(analysis)
      
      if complexity_score > 100
        Rails.logger.warn "High complexity query detected: #{analysis.inspect}"
      end
      
      analysis.merge(score: complexity_score)
    end
    
    private
    
    def count_joins(scope)
      scope.joins_values.size + scope.left_outer_joins_values.size
    end
    
    def count_conditions(scope)
      scope.where_clause.predicates.size
    end
    
    def count_aggregations(scope)
      sql = scope.to_sql
      sql.scan(/COUNT|SUM|AVG|MAX|MIN|GROUP BY/i).size
    end
    
    def count_subqueries(scope)
      sql = scope.to_sql
      sql.scan(/\(\s*SELECT/i).size
    end
    
    def calculate_complexity_score(analysis)
      (analysis[:joins] * 10) +
        (analysis[:conditions] * 2) +
        (analysis[:aggregations] * 5) +
        (analysis[:subqueries] * 20)
    end
  end
  
  # Instance methods for record-level security
  def validate_query_security
    # Add any record-level security validations here
    true
  end
  
  def query_security_enabled?
    self.class.table_exists? && 
      Rails.application.config.respond_to?(:enable_query_security) &&
      Rails.application.config.enable_query_security
  end
  
  # Simple in-memory rate limit store for development
  class MemoryRateLimitStore
    def initialize
      @store = {}
      @expires = {}
    end
    
    def get(key)
      cleanup_expired
      @store[key]
    end
    
    def setex(key, ttl, value)
      @store[key] = value
      @expires[key] = Time.current + ttl.seconds
      value
    end
    
    def incr(key)
      @store[key] = (@store[key] || 0) + 1
    end
    
    def exists?(key)
      cleanup_expired
      @store.key?(key)
    end
    
    private
    
    def cleanup_expired
      now = Time.current
      @expires.each do |key, expire_time|
        if expire_time <= now
          @store.delete(key)
          @expires.delete(key)
        end
      end
    end
  end
end