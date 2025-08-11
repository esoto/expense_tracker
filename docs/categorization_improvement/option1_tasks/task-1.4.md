### Task 1.4: Fuzzy Matching Implementation
**Priority**: High  
**Estimated Hours**: 5  
**Dependencies**: Task 1.3  

#### Description
Implement fuzzy string matching algorithms for merchant name variations.

#### Acceptance Criteria
- [ ] Jaro-Winkler distance implementation
- [ ] Levenshtein distance as fallback
- [ ] Trigram similarity using PostgreSQL
- [ ] Configurable similarity thresholds
- [ ] Performance: < 10ms per match
- [ ] Handle Spanish and English text

#### Technical Implementation
```ruby
# app/services/categorization/matchers/fuzzy_matcher.rb
class Categorization::Matchers::FuzzyMatcher
  def initialize(threshold: 0.8)
    @threshold = threshold
    @jaro = FuzzyStringMatch::JaroWinkler.create(:pure)
  end
  
  def find_best_match(text, patterns)
    normalized_text = normalize(text)
    
    matches = patterns.map do |pattern|
      score = calculate_similarity(normalized_text, pattern.pattern_value)
      { pattern: pattern, score: score }
    end
    
    best_match = matches.max_by { |m| m[:score] }
    
    return nil if best_match[:score] < @threshold
    
    MatchResult.new(
      pattern: best_match[:pattern],
      confidence: best_match[:score],
      match_type: determine_match_type(best_match[:score])
    )
  end
  
  private
  
  def normalize(text)
    text.downcase
        .gsub(/[^\w\s]/, ' ')  # Remove special chars
        .gsub(/\b\d{4,}\b/, '') # Remove long numbers
        .strip
        .squeeze(' ')
  end
  
  def calculate_similarity(text1, text2)
    # Try exact match first
    return 1.0 if text1 == text2
    
    # Jaro-Winkler for close matches
    jw_score = @jaro.getDistance(text1, text2)
    
    # Trigram similarity as secondary measure
    trgm_score = trigram_similarity(text1, text2)
    
    # Weighted average
    (jw_score * 0.7 + trgm_score * 0.3)
  end
  
  def trigram_similarity(text1, text2)
    trgm1 = text1.chars.each_cons(3).map(&:join).to_set
    trgm2 = text2.chars.each_cons(3).map(&:join).to_set
    
    intersection = (trgm1 & trgm2).size
    union = (trgm1 | trgm2).size
    
    return 0.0 if union.zero?
    intersection.to_f / union
  end
end
```
