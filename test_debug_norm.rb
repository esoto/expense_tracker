# Debug what's happening with normalization
require 'pp'

class DebugMatcher < Categorization::Matchers::FuzzyMatcher
  def perform_matching(text, candidates, options)
    puts "\n=== DEBUG perform_matching ==="
    puts "Input text: '#{text}'"
    puts "Options normalize_text: #{options[:normalize_text].inspect}"
    puts "Instance normalize_text: #{@options[:normalize_text].inspect}"

    should_normalize = options[:normalize_text]
    should_normalize = @options[:normalize_text] if should_normalize.nil?
    puts "Should normalize: #{should_normalize}"

    candidates.each do |candidate|
      candidate_text = @text_extractor.extract_from(candidate)
      processed_candidate = should_normalize ? @normalizer.normalize(candidate_text) : candidate_text

      puts "\nCandidate: '#{candidate_text}'"
      puts "Processed: '#{processed_candidate}'"

      # Calculate similarity
      score = calculate_similarity_raw(text, processed_candidate, :jaro_winkler)
      puts "Score: #{score}"
    end

    super(text, candidates, options)
  end
end

matcher = DebugMatcher.new(normalize_text: true, enable_caching: false)
candidates = [ "STARBUCKS" ]

puts "Test 1: With normalization enabled (default)"
result = matcher.match("starbucks", candidates)
puts "Result matches: #{result.matches.count}"

puts "\n" + "="*50

puts "\nTest 2: With normalization disabled via options"
result = matcher.match("STARBUCKS", candidates, normalize_text: false)
puts "Result matches: #{result.matches.count}"
puts "Best score: #{result.best_score}"

puts "\nTest 3: Case mismatch with normalization disabled"
result = matcher.match("starbucks", candidates, normalize_text: false)
puts "Result matches: #{result.matches.count}"
puts "Best score: #{result.best_score}"
