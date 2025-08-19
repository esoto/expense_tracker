# frozen_string_literal: true

require "fuzzystringmatch"

module Categorization
  module Matchers
    # High-performance fuzzy matching service for merchant name and pattern matching
    # Implements multiple matching algorithms with configurable thresholds
    # Optimized for < 10ms performance per match with caching and pre-processing
    class FuzzyMatcher
      include ActiveSupport::Benchmarkable

      # Algorithm configuration
      ALGORITHMS = {
        jaro_winkler: { threshold: 0.85, weight: 1.2 },
        levenshtein: { threshold: 0.75, weight: 0.8 },
        trigram: { threshold: 0.7, weight: 1.0 },
        phonetic: { threshold: 0.9, weight: 0.6 }
      }.freeze

      # Default configuration
      DEFAULT_OPTIONS = {
        algorithms: [ :jaro_winkler, :trigram ],
        min_confidence: 0.6,
        max_results: 5,
        timeout_ms: 10,
        enable_caching: true,
        normalize_text: true,
        handle_spanish: true
      }.freeze

      # Performance monitoring
      PERFORMANCE_THRESHOLD_MS = 10
      CACHE_TTL = 1.hour

      # Text normalization patterns
      SPANISH_CHARS = {
        "á" => "a", "é" => "e", "í" => "i", "ó" => "o", "ú" => "u",
        "ñ" => "n", "ü" => "u",
        "Á" => "A", "É" => "E", "Í" => "I", "Ó" => "O", "Ú" => "U",
        "Ñ" => "N", "Ü" => "U"
      }.freeze

      # Pre-compiled noise patterns for better performance
      NOISE_PATTERNS = [
        /\b(INC|LLC|LTD|CORP|CO|S\.A\.|C\.V\.)\b/i,
        /\*+/,
        /\s+#\d+/,
        /\s+\d{4,}$/,
        /^(PAYPAL|SQ|SQUARE|TST|POS|CCD)\s*\*/i
      ].freeze

      class << self
        # Get or create a default instance (for services that haven't migrated to DI yet)
        def instance
          @default_instance ||= new
        end

        # Factory method for creating matcher instances
        def create(options = {})
          new(options)
        end
      end

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.merge(options)
        @jaro_winkler = FuzzyStringMatch::JaroWinkler.create(:native)
        @cache = build_cache if @options[:enable_caching]
        @metrics_collector = MetricsCollector.new
        @text_extractor = TextExtractor.new

        # Check PostgreSQL extension availability once at initialization
        @pg_trgm_available = check_pg_extension("pg_trgm")
        @unaccent_available = check_pg_extension("unaccent")

        # Pass options to normalizer so it respects normalize_text setting
        @normalizer = TextNormalizer.new(@options, @unaccent_available)

        Rails.logger.info "[FuzzyMatcher] Initialized with algorithms: #{@options[:algorithms].join(', ')}"
        Rails.logger.info "[FuzzyMatcher] PostgreSQL extensions - pg_trgm: #{@pg_trgm_available}, unaccent: #{@unaccent_available}"
      end

      # Main matching method - finds best matches for given text
      def match(text, candidates, options = {})
        return MatchResult.empty if text.blank? || candidates.blank?

        opts = @options.merge(options)

        benchmark_match("match") do
          # Single point of control for normalization
          # Properly handle the normalize_text option
          should_normalize = opts[:normalize_text]
          should_normalize = @options[:normalize_text] if should_normalize.nil?

          processed_text = should_normalize ? @normalizer.normalize(text) : text

          # Check cache first
          if opts[:enable_caching] && @cache
            cache_key = cache_key_for(processed_text, candidates)
            cached_result = @cache.read(cache_key)

            if cached_result
              @metrics_collector.record_cache_hit
              return cached_result
            end
          end

          # Perform matching
          results = perform_matching(processed_text, candidates, opts)

          # Cache the result
          if opts[:enable_caching] && @cache
            @cache.write(cache_key, results, expires_in: CACHE_TTL)
          end

          results
        end
      rescue Timeout::Error
        Rails.logger.warn "[FuzzyMatcher] Match operation timed out after #{opts[:timeout_ms]}ms"
        MatchResult.timeout
      rescue => e
        Rails.logger.error "[FuzzyMatcher] Error during matching: #{e.message}"
        MatchResult.error(e.message)
      end

      # Match against categorization patterns
      def match_pattern(text, patterns, options = {})
        return MatchResult.empty if text.blank? || patterns.blank?

        benchmark_match("match_pattern") do
          # Respect normalization option passed to match_pattern
          opts = @options.merge(options)
          should_normalize = opts[:normalize_text]
          should_normalize = @options[:normalize_text] if should_normalize.nil?

          processed_text = should_normalize ? @normalizer.normalize(text) : text

          # Check if we should use word-based matching for better search results
          # This is useful when searching for patterns containing specific words
          use_word_matching = opts[:enable_word_matching] || false

          # Build pattern candidates and index for fast lookup
          pattern_candidates = []
          pattern_index = {}

          patterns.each do |pattern|
            candidate = {
              id: pattern.id,
              text: pattern.pattern_value,
              type: pattern.pattern_type,
              category_id: pattern.category_id,
              confidence_weight: pattern.confidence_weight
            }
            pattern_candidates << candidate
            pattern_index[pattern.id] = pattern
          end

          # First try standard fuzzy matching
          result = match(processed_text, pattern_candidates, options)

          # If word matching is enabled or we have few results, also check for word containment
          if use_word_matching || result.matches.size < 2
            # Also find patterns that contain the search term as a word
            word_matches = find_word_matches_optimized(processed_text, patterns, opts)

            # Merge word matches with fuzzy matches
            existing_ids = result.matches.map { |m| m[:id] }.to_set

            word_matches.each do |word_match|
              unless existing_ids.include?(word_match[:id])
                result.matches << word_match
              end
            end
          end

          # Adjust scores based on pattern confidence using pre-built index
          result.matches.each do |match_item|
            pattern = pattern_index[match_item[:id]]
            if pattern
              match_item[:adjusted_score] = match_item[:score] * pattern.effective_confidence
              match_item[:pattern] = pattern
            end
          end

          # Re-sort by adjusted score
          result.matches.sort_by! { |m| -m[:adjusted_score] }

          # Limit to max_results - create new MatchResult with limited matches
          if opts[:max_results] && result.matches.size > opts[:max_results]
            limited_matches = result.matches.first(opts[:max_results])
            return MatchResult.new(
              success: result.success?,
              matches: limited_matches,
              query_text: result.query_text,
              algorithm_used: result.algorithm_used,
              metadata: result.metadata
            )
          end

          result
        end
      end

      # Match merchant names
      def match_merchant(merchant_name, canonical_merchants, options = {})
        return MatchResult.empty if merchant_name.blank? || canonical_merchants.blank?

        benchmark_match("match_merchant") do
          normalized_merchant = @normalizer.normalize_merchant(merchant_name)

          merchant_candidates = canonical_merchants.map do |merchant|
            {
              id: merchant.id,
              text: merchant.name,
              display_name: merchant.display_name,
              usage_count: merchant.usage_count
            }
          end

          result = match(normalized_merchant, merchant_candidates, options)

          # Boost popular merchants
          result.matches.each do |match_item|
            merchant = canonical_merchants.find { |m| m.id == match_item[:id] }
            if merchant && merchant.usage_count > 10
              popularity_boost = Math.log10(merchant.usage_count) * 0.05
              match_item[:adjusted_score] = [ match_item[:score] + popularity_boost, 1.0 ].min
            else
              # Ensure adjusted_score is always set
              match_item[:adjusted_score] = match_item[:score]
            end
          end

          # Re-sort by adjusted score
          result.matches.sort_by! { |m| -(m[:adjusted_score] || m[:score]) }

          result
        end
      end

      # Batch matching for multiple texts
      def batch_match(texts, candidates, options = {})
        return [] if texts.blank? || candidates.blank?

        benchmark_match("batch_match") do
          texts.map { |text| match(text, candidates, options) }
        end
      end

      # Calculate similarity between two strings using specified algorithm
      def calculate_similarity(text1, text2, algorithm = :jaro_winkler)
        return 0.0 if text1.blank? || text2.blank?

        normalized1 = @normalizer.normalize(text1)
        normalized2 = @normalizer.normalize(text2)

        calculate_similarity_raw(normalized1, normalized2, algorithm)
      end

      # Calculate similarity on already-processed text (no normalization)
      def calculate_similarity_raw(text1, text2, algorithm = :jaro_winkler)
        return 0.0 if text1.blank? || text2.blank?

        case algorithm
        when :jaro_winkler
          calculate_jaro_winkler(text1, text2)
        when :levenshtein
          calculate_levenshtein(text1, text2)
        when :trigram
          calculate_trigram(text1, text2)
        when :phonetic
          calculate_phonetic(text1, text2)
        else
          raise ArgumentError, "Unknown algorithm: #{algorithm}"
        end
      end

      # Get performance metrics
      def metrics
        @metrics_collector.summary.merge(
          cache_enabled: @options[:enable_caching],
          algorithms: @options[:algorithms],
          performance_threshold_ms: PERFORMANCE_THRESHOLD_MS
        )
      end

      # Clear the cache
      def clear_cache
        @cache&.clear
        Rails.logger.info "[FuzzyMatcher] Cache cleared"
      end

      private

      def perform_matching(text, candidates, options)
        matches = []
        min_confidence = options[:min_confidence]

        # Early termination threshold - if we find high confidence matches,
        # we can skip processing remaining candidates
        high_confidence_threshold = 0.95
        high_confidence_count = 0
        max_matches_to_process = 100 # Limit processing for performance

        # Check normalization setting once - consistent with match method
        should_normalize = options[:normalize_text]
        should_normalize = @options[:normalize_text] if should_normalize.nil?

        # Pre-calculate text length for reuse
        text_length = text.length

        # Limit candidates to process for performance
        candidates_to_process = candidates.take(max_matches_to_process)

        candidates_to_process.each do |candidate|
          candidate_text = @text_extractor.extract_from(candidate)
          next if candidate_text.blank?

          # Apply normalization based on single control point
          processed_candidate = should_normalize ? @normalizer.normalize(candidate_text) : candidate_text

          # Quick length check - if lengths are very different, skip expensive calculations
          candidate_length = processed_candidate.length
          min_length = [ text_length, candidate_length ].min
          max_length = [ text_length, candidate_length ].max

          # Skip if length difference is too great (unlikely to be good match)
          next if max_length > 0 && (min_length.to_f / max_length) < 0.3

          # For very short strings, require higher similarity
          adjusted_min_confidence = text_length < 5 ? [ min_confidence * 1.2, 0.9 ].min : min_confidence

          # Calculate scores using selected algorithms
          scores = {}
          options[:algorithms].each do |algorithm|
            # Pass already processed text to avoid double normalization
            score = calculate_similarity_raw(text, processed_candidate, algorithm)

            # Early termination within algorithm loop if score is too low
            break if score < adjusted_min_confidence * 0.7

            scores[algorithm] = score
          end

          next if scores.empty?

          # Calculate weighted average score
          weighted_score = calculate_weighted_score(scores)

          # Add to matches if above threshold
          if weighted_score >= adjusted_min_confidence
            matches << build_match_item(candidate, weighted_score, scores)

            # Track high confidence matches for early termination
            if weighted_score >= high_confidence_threshold
              high_confidence_count += 1
              break if high_confidence_count >= options[:max_results]
            end
          end
        end

        # Sort by score and limit results
        matches.sort_by! { |m| -m[:score] }
        matches = matches.first(options[:max_results])

        MatchResult.new(
          success: true,
          matches: matches,
          algorithm_used: options[:algorithms],
          query_text: text
        )
      end

      def calculate_jaro_winkler(text1, text2)
        return 0.0 if text1.blank? || text2.blank?
        return 1.0 if text1 == text2

        # Use the fuzzy-string-match gem's optimized C implementation
        # The gem already implements proper Jaro-Winkler with prefix boost
        score = @jaro_winkler.getDistance(text1, text2)

        # Return the score as-is - the gem's implementation is mathematically correct
        # It already includes Winkler's prefix modification properly
        score
      rescue => e
        Rails.logger.error "[FuzzyMatcher] Jaro-Winkler calculation error: #{e.message}"
        0.0
      end

      def calculate_levenshtein(text1, text2)
        return 0.0 if text1.blank? || text2.blank?

        max_length = [ text1.length, text2.length ].max
        return 1.0 if max_length == 0

        distance = levenshtein_distance(text1, text2)
        1.0 - (distance.to_f / max_length)
      end

      def levenshtein_distance(str1, str2)
        m = str1.length
        n = str2.length

        return n if m == 0
        return m if n == 0

        # Create matrix
        d = Array.new(m + 1) { Array.new(n + 1) }

        # Initialize first column and row
        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }

        # Calculate distances
        (1..n).each do |j|
          (1..m).each do |i|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,      # deletion
              d[i][j - 1] + 1,      # insertion
              d[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        d[m][n]
      end

      def calculate_trigram(text1, text2)
        return 0.0 if text1.blank? || text2.blank?

        # Always use Ruby implementation to avoid database queries in hot path
        # This is much faster for individual comparisons than DB roundtrips
        trigrams1 = extract_trigrams(text1)
        trigrams2 = extract_trigrams(text2)

        return 0.0 if trigrams1.empty? || trigrams2.empty?

        # Use Set for O(1) lookup performance
        set1 = trigrams1.to_set
        set2 = trigrams2.to_set

        intersection = (set1 & set2).size
        union = (set1 | set2).size

        union > 0 ? intersection.to_f / union : 0.0
      end

      def extract_trigrams(text)
        return [] if text.length < 3

        # Pre-allocate array for better performance
        padded = "  #{text}  "
        trigrams = Array.new(padded.length - 2)

        (0..padded.length - 3).each do |i|
          trigrams[i] = padded[i, 3]
        end

        trigrams
      end

      def calculate_phonetic(text1, text2)
        # Simple phonetic matching using Soundex-like algorithm
        phonetic1 = phonetic_encode(text1)
        phonetic2 = phonetic_encode(text2)

        phonetic1 == phonetic2 ? 1.0 : 0.0
      end

      def phonetic_encode(text)
        return "" if text.blank?

        # Simple phonetic encoding (similar to Soundex)
        encoded = text.upcase.gsub(/[^A-Z]/, "")
        return "" if encoded.blank?

        # Keep first letter
        first_char = encoded[0]
        rest = encoded[1..-1] || ""

        # Remove vowels and certain consonants
        rest.gsub!(/[AEIOUHWY]/, "")

        # Replace similar sounding consonants
        rest.tr!("BFPV", "1")
        rest.tr!("CGJKQSXZ", "2")
        rest.tr!("DT", "3")
        rest.tr!("L", "4")
        rest.tr!("MN", "5")
        rest.tr!("R", "6")

        # Remove consecutive duplicates
        rest.squeeze!

        # Pad or truncate to 4 characters
        result = "#{first_char}#{rest}".ljust(4, "0")
        result[0, 4]
      end

      def calculate_weighted_score(scores)
        return 0.0 if scores.empty?

        total_weight = 0.0
        weighted_sum = 0.0

        scores.each do |algorithm, score|
          weight = ALGORITHMS[algorithm][:weight]
          weighted_sum += score * weight
          total_weight += weight
        end

        total_weight > 0 ? weighted_sum / total_weight : 0.0
      end

      def extract_text(candidate)
        @text_extractor.extract_from(candidate)
      end

      def build_match_item(candidate, score, algorithm_scores)
        item = {
          score: score.round(4),
          algorithm_scores: algorithm_scores.transform_values { |v| v.round(4) }
        }

        # Extract text for all candidates to ensure consistency
        extracted_text = @text_extractor.extract_from(candidate)

        case candidate
        when Hash
          # For hashes, preserve the text field if present, otherwise use extracted text
          merged_item = item.merge(candidate)
          merged_item[:text] ||= extracted_text if extracted_text
          merged_item
        when String
          item.merge(text: candidate)
        else
          # For objects (like Expense), always use the extracted text
          item.merge(
            id: candidate.try(:id),
            text: extracted_text,
            object: candidate
          )
        end
      end

      def find_word_matches(search_text, patterns, options)
        # Keep for backward compatibility, delegate to optimized version
        find_word_matches_optimized(search_text, patterns, options)
      end

      def find_word_matches_optimized(search_text, patterns, options)
        return [] if search_text.blank? || patterns.empty?

        matches = []
        min_confidence = options[:min_confidence] || 0.70
        max_patterns_to_check = 20 # Limit for performance

        # Pre-process search text once
        search_lower = search_text.downcase
        search_words = search_lower.split(/\s+/).select { |w| w.length >= 3 }
        return [] if search_words.empty?

        # Create word set for O(1) lookups
        search_word_set = search_words.to_set

        # Only check first N patterns for word matches to maintain performance
        patterns_to_check = patterns.take(max_patterns_to_check)

        # Process patterns with early termination
        patterns_to_check.each do |pattern|
          # Skip if we already have enough high-quality matches
          break if matches.size >= 5

          pattern_value = pattern.pattern_value
          next if pattern_value.blank?

          pattern_text = pattern_value.downcase

          # Quick check: if pattern doesn't contain any search words, skip
          has_match = false
          best_word_score = 0.0

          # First, check for exact word matches (fastest)
          pattern_words = pattern_text.split(/\s+/)

          # Check for any exact word match
          if (search_word_set & pattern_words.to_set).any?
            has_match = true
            best_word_score = 1.0
          elsif search_words.any? { |sw| sw.length >= 4 && pattern_text.include?(sw) }
            # Only do substring matching for longer words
            has_match = true
            # Use a simplified score for substring matches
            best_word_score = 0.8
          end

          if has_match && best_word_score >= 0.7
            # Create a match with appropriate score
            # Word matches get slightly lower scores than exact fuzzy matches
            adjusted_score = best_word_score * 0.85

            if adjusted_score >= min_confidence
              matches << {
                id: pattern.id,
                text: pattern_value,
                score: adjusted_score.round(4),
                algorithm_scores: { word_match: best_word_score.round(4) },
                pattern: pattern,
                category_id: pattern.category_id
              }
            end
          end
        end

        # Return matches as-is, already limited
        matches
      end

      def cache_key_for(text, candidates)
        candidate_ids = candidates.map do |c|
          c.is_a?(Hash) ? c[:id] : c.try(:id)
        end.compact.sort.join("-")

        "fuzzy_match:#{Digest::MD5.hexdigest(text)}:#{Digest::MD5.hexdigest(candidate_ids)}"
      end

      def build_cache
        if defined?(Redis) && Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
          Rails.cache
        else
          ActiveSupport::Cache::MemoryStore.new(
            size: 10.megabytes,
            compress: false
          )
        end
      end

      def check_pg_extension(extension_name)
        ActiveRecord::Base.connection.extension_enabled?(extension_name)
      rescue => e
        Rails.logger.warn "[FuzzyMatcher] Could not check #{extension_name} extension: #{e.message}"
        false
      end

      def benchmark_match(operation, &block)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = yield

        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        @metrics_collector.record_operation(operation, duration_ms)

        if duration_ms > PERFORMANCE_THRESHOLD_MS
          Rails.logger.warn "[FuzzyMatcher] Slow operation: #{operation} took #{duration_ms.round(2)}ms"
        end

        result
      end

      # Text normalization helper
      class TextNormalizer
        def initialize(options, unaccent_available = false)
          @options = options
          @unaccent_available = unaccent_available

          # Pre-build normalization table for O(1) lookups
          @spanish_normalization = SPANISH_CHARS.dup if @options[:handle_spanish]

          # Cache normalized text to avoid redundant processing
          @normalization_cache = {}
        end

        def normalize(text)
          return "" if text.blank?

          # The FuzzyMatcher class controls when to call normalize
          # This method always normalizes when called

          # Check cache first
          cached = @normalization_cache[text]
          return cached if cached

          normalized = text.dup

          # Handle Spanish characters using Ruby-only implementation
          if @options[:handle_spanish]
            normalized = normalize_spanish_ruby(normalized)
          end

          # Remove noise patterns
          NOISE_PATTERNS.each do |pattern|
            normalized.gsub!(pattern, " ")
          end

          # Clean up
          normalized.downcase!
          normalized.gsub!(/[^\w\s]/, " ")
          normalized.squeeze!(" ")
          normalized.strip!

          # Cache the result
          @normalization_cache[text] = normalized if @normalization_cache.size < 1000

          normalized
        end

        def normalize_merchant(merchant_name)
          return "" if merchant_name.blank?

          # Use the existing CanonicalMerchant normalization
          CanonicalMerchant.normalize_merchant_name(merchant_name)
        end

        # Batch normalization for PostgreSQL when processing many items
        def normalize_batch_with_db(texts)
          return [] if texts.empty? || !@unaccent_available

          # Only use database for batch operations, not individual matches
          sql = texts.map { |text|
            ActiveRecord::Base.sanitize_sql_array([ "SELECT ? AS original, unaccent(?) AS normalized", text, text ])
          }.join(" UNION ALL ")

          results = ActiveRecord::Base.connection.execute(sql)

          result_hash = {}
          results.each { |row| result_hash[row["original"]] = row["normalized"] }

          texts.map { |text| result_hash[text] || text }
        rescue => e
          Rails.logger.error "[TextNormalizer] Batch normalization failed: #{e.message}"
          texts
        end

        private

        def normalize_spanish_ruby(text)
          # Use Ruby-only implementation - NO DATABASE QUERIES
          # This is much faster for individual strings than DB roundtrips
          normalized = text.dup

          # Use single pass through string with translation table
          if @spanish_normalization
            @spanish_normalization.each do |spanish_char, ascii_char|
              normalized.gsub!(spanish_char, ascii_char)
            end
          end

          normalized
        end
      end

      # Metrics collector
      class MetricsCollector
        def initialize
          @operations = Hash.new { |h, k| h[k] = [] }
          @cache_hits = 0
          @cache_misses = 0
          @lock = Mutex.new
        end

        def record_operation(name, duration_ms)
          @lock.synchronize do
            @operations[name] << duration_ms
            @operations[name].shift if @operations[name].size > 1000
          end
        end

        def record_cache_hit
          @lock.synchronize { @cache_hits += 1 }
        end

        def record_cache_miss
          @lock.synchronize { @cache_misses += 1 }
        end

        def summary
          @lock.synchronize do
            {
              operations: operation_stats,
              cache: {
                hits: @cache_hits,
                misses: @cache_misses,
                hit_rate: cache_hit_rate
              }
            }
          end
        end

        private

        def operation_stats
          @operations.transform_values do |durations|
            next { count: 0 } if durations.empty?

            {
              count: durations.size,
              avg_ms: (durations.sum / durations.size).round(3),
              min_ms: durations.min.round(3),
              max_ms: durations.max.round(3),
              p95_ms: percentile(durations, 0.95).round(3),
              p99_ms: percentile(durations, 0.99).round(3)
            }
          end
        end

        def percentile(values, pct)
          return 0 if values.empty?

          sorted = values.sort
          index = (pct * sorted.size).ceil - 1
          sorted[index] || sorted.last
        end

        def cache_hit_rate
          total = @cache_hits + @cache_misses
          total > 0 ? (@cache_hits.to_f / total * 100).round(2) : 0.0
        end
      end
    end

    # Health check for service monitoring
    def healthy?
      @healthy ||= begin
        # Test basic matching functionality
        test_result = match("test", [ "test" ])
        test_result.is_a?(MatchResult)
      rescue => e
        Rails.logger.error "[FuzzyMatcher] Health check failed: #{e.message}"
        false
      end
    end

    # Reset internal state
    def reset!
      @cache&.clear if @options[:enable_caching]
      @metrics_collector = MetricsCollector.new
      @normalizer.instance_variable_set(:@normalization_cache, {}) if @normalizer
      @healthy = nil
      Rails.logger.info "[FuzzyMatcher] Service reset completed"
    rescue => e
      Rails.logger.error "[FuzzyMatcher] Reset failed: #{e.message}"
    end

    # Get service metrics
    def metrics
      base_metrics = @metrics_collector.summary
      # Add matches_performed count
      base_metrics[:matches_performed] = base_metrics.dig(:operations, :match)&.fetch(:count, 0) || 0
      base_metrics
    end
  end
end
