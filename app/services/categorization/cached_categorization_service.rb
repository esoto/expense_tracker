# frozen_string_literal: true

module Categorization
  # Enhanced categorization service that leverages the pattern cache for high performance
  # This service wraps the existing CategorizationService with cache-aware operations
  class CachedCategorizationService < ::CategorizationService
    def initialize
      super
      @cache = PatternCache.instance
    end
    
    # Override the categorize_expense method to use cached patterns
    def categorize_expense(expense)
      return { category: nil, confidence: 0, method: "no_match", error: "Invalid expense" } if expense.nil?
      
      begin
        # Check cached user preferences first (most specific)
        if expense.merchant_name.present?
          user_pref = @cache.get_user_preference(expense.merchant_name)
          if user_pref
            # Convert preference_weight to confidence (normalize to 0-1 range)
            confidence = [user_pref.preference_weight / 10.0, 1.0].min
            update_expense(expense, user_pref.category, confidence, "user_preference")
            return {
              category: user_pref.category,
              confidence: confidence,
              method: "user_preference",
              patterns_used: [],
              cache_stats: { hits: 1, source: "memory" }
            }
          end
        end
        
        # Use cached patterns for matching
        pattern_matches = find_cached_pattern_matches(expense)
        composite_matches = find_cached_composite_matches(expense)
        
        # Combine and score matches
        all_matches = combine_matches(pattern_matches, composite_matches)
        
        if all_matches.empty?
          return { 
            category: nil, 
            confidence: 0, 
            method: "no_match", 
            patterns_used: [],
            cache_stats: {
              hit_rate: @cache.hit_rate,
              operations: @cache.metrics[:operations]["get_all_active_patterns"] || {}
            }
          }
        end
        
        # Sort by confidence score
        sorted_matches = all_matches.sort_by { |m| -m[:score] }
        best_match = sorted_matches.first
        
        # Update expense if confidence is high enough
        if best_match[:score] > 0.5
          update_expense(expense, best_match[:category], best_match[:score], best_match[:method])
        end
        
        {
          category: best_match[:category],
          confidence: best_match[:score],
          method: best_match[:method],
          patterns_used: best_match[:patterns],
          alternative_categories: sorted_matches[1..2].compact.map do |match|
            { category: match[:category], confidence: match[:score] }
          end,
          cache_stats: {
            hit_rate: @cache.hit_rate,
            operations: @cache.metrics[:operations]["get_pattern"] || {}
          }
        }
      rescue StandardError => e
        Rails.logger.error "Categorization error: #{e.message}"
        { category: nil, confidence: 0, method: "error", error: "Database error: #{e.message}" }
      end
    end
    
    # Optimized bulk categorization with cache preloading
    def bulk_categorize(expenses)
      return [] if expenses.blank?
      
      # Preload cache for all expenses
      @cache.preload_for_expenses(expenses)
      
      # Process expenses
      results = expenses.map do |expense|
        categorize_expense(expense)
      end
      
      # Log cache performance for bulk operation
      log_bulk_performance(expenses.size)
      
      results
    end
    
    # Get cache performance metrics
    def cache_metrics
      @cache.metrics
    end
    
    # Warm the cache (useful for initialization or after deployments)
    def warm_cache
      @cache.warm_cache
    end
    
    private
    
    def find_cached_pattern_matches(expense)
      matches = []
      
      # Get all active patterns from cache
      patterns = @cache.get_all_active_patterns
      
      patterns.each do |pattern|
        if pattern.matches?(expense)
          score = pattern.effective_confidence
          matches << {
            category: pattern.category,
            score: score,
            method: "pattern_matching",
            patterns: ["#{pattern.pattern_type}:#{pattern.pattern_value}"]
          }
        end
      end
      
      matches
    end
    
    def find_cached_composite_matches(expense)
      matches = []
      
      # Fetch composite patterns (these are less common, so we can fetch from DB with caching)
      CompositePattern.active.find_each do |composite|
        # Use cache for the composite pattern
        cached_composite = @cache.get_composite_pattern(composite.id)
        next unless cached_composite
        next unless cached_composite.matches?(expense)
        
        score = cached_composite.effective_confidence
        matches << {
          category: cached_composite.category,
          score: score,
          method: "composite_pattern",
          patterns: ["composite:#{cached_composite.name}"]
        }
      end
      
      matches
    end
    
    def log_bulk_performance(count)
      metrics = @cache.metrics
      
      Rails.logger.info "[CachedCategorizationService] Bulk categorization completed: " \
                       "#{count} expenses, " \
                       "Hit rate: #{metrics[:hit_rate]}%, " \
                       "Memory hits: #{metrics[:hits][:memory]}, " \
                       "Redis hits: #{metrics[:hits][:redis]}, " \
                       "Misses: #{metrics[:misses]}"
      
      # Log slow operations if any
      if metrics[:operations]
        slow_ops = metrics[:operations].select { |_, stats| stats[:avg_ms] && stats[:avg_ms] > 1.0 }
        if slow_ops.any?
          Rails.logger.warn "[CachedCategorizationService] Slow operations detected: #{slow_ops.inspect}"
        end
      end
    end
  end
end