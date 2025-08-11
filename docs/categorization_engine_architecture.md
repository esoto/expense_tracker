# Categorization Engine Architecture

## Overview

The Categorization Engine is the main orchestrator service that integrates all categorization components into a cohesive system. It provides a clean, performant API for expense categorization with a target performance of <10ms per categorization.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Categorization::Engine                       │
│                        (Orchestrator)                            │
├─────────────────────────────────────────────────────────────────┤
│  - Singleton pattern for consistent state                        │
│  - Main entry point: categorize(expense, options)               │
│  - Coordinates all sub-services                                  │
│  - Performance tracking & metrics                                │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ├──────────────┬──────────────┬──────────────┬──────────────┐
               ▼              ▼              ▼              ▼              ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  PatternCache    │ │ FuzzyMatcher │ │ Confidence   │ │ Pattern      │ │ Performance  │
│                  │ │              │ │ Calculator   │ │ Learner      │ │ Tracker      │
├──────────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤
│ Two-tier cache   │ │ Multi-algo   │ │ Multi-factor │ │ Learning     │ │ Metrics      │
│ (Memory + Redis) │ │ text matching│ │ scoring      │ │ from feedback│ │ collection   │
│ <1ms lookups     │ │ Jaro-Winkler │ │ 5 factors    │ │ Pattern CRUD │ │ Performance  │
│                  │ │ Levenshtein  │ │ Sigmoid norm │ │              │ │ monitoring   │
└──────────────────┘ └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

## Service Integration Flow

### 1. Categorization Flow

```
categorize(expense) →
  1. Check user preferences (via PatternCache)
  2. Find pattern matches (via FuzzyMatcher)
  3. Calculate confidence scores (via ConfidenceCalculator)
  4. Select best category
  5. Build result with alternatives
  6. Auto-update expense if configured
  7. Track performance metrics
```

### 2. Learning Flow

```
learn_from_correction(expense, correct_category, predicted_category) →
  1. Pass to PatternLearner
  2. Create/update patterns
  3. Strengthen/weaken existing patterns
  4. Invalidate cache
  5. Return learning result
```

## Key Components

### Categorization::Engine

**Responsibilities:**
- Service orchestration
- Request routing
- Performance monitoring
- State management
- Error handling cascade

**Key Methods:**
- `categorize(expense, options)` - Main categorization entry point
- `batch_categorize(expenses, options)` - Bulk processing
- `learn_from_correction(...)` - Learning from feedback
- `warm_up()` - Cache preloading
- `metrics()` - Performance & health metrics
- `reset!()` - Clear all caches and state

### CategorizationResult

Value object that encapsulates the categorization result:

```ruby
{
  category: Category,
  confidence: 0.85,
  patterns_used: ["merchant:whole foods", "keyword:grocery"],
  confidence_breakdown: {
    text_match: { value: 0.9, weight: 0.35, contribution: 0.315 },
    historical_success: { value: 0.8, weight: 0.25, contribution: 0.2 },
    # ...
  },
  alternative_categories: [
    { category: Category, confidence: 0.65 }
  ],
  processing_time_ms: 8.5,
  cache_hits: 3,
  method: "pattern_match"
}
```

### PerformanceTracker

Monitors and ensures performance targets:

- Tracks individual operation times
- Maintains performance statistics
- Alerts on slow operations (>10ms)
- Provides optimization suggestions
- Cache hit/miss tracking

## Service Dependencies

### Injected Services

All services are injected via constructor, allowing for testing and customization:

```ruby
engine = Categorization::Engine.new(
  pattern_cache: custom_cache,
  fuzzy_matcher: custom_matcher,
  confidence_calculator: custom_calculator,
  pattern_learner: custom_learner,
  performance_tracker: custom_tracker
)
```

### Default Services

- **PatternCache**: Two-tier caching (Memory + Redis)
- **FuzzyMatcher**: Multi-algorithm text matching
- **ConfidenceCalculator**: 5-factor confidence scoring
- **PatternLearner**: ML-inspired pattern learning
- **PerformanceTracker**: Comprehensive metrics

## Performance Characteristics

### Target Metrics
- Single categorization: <10ms
- Batch of 100: <1s
- Cache hit rate: >70%
- Success rate: >85%

### Optimization Strategies
1. **Cache Preloading**: Warm cache on startup
2. **Batch Processing**: Preload patterns for multiple expenses
3. **Early Termination**: Stop processing when high confidence found
4. **Tiered Caching**: Memory (L1) + Redis (L2)
5. **Lazy Loading**: Load patterns on demand

## Error Handling

### Error Cascade
1. Service-level errors are caught and logged
2. Graceful degradation (e.g., Redis unavailable → memory only)
3. Always return valid CategorizationResult
4. Never throw exceptions to caller

### Error Types
- `Invalid expense` - Nil or invalid expense object
- `No match found` - No patterns matched
- `Low confidence` - Below threshold
- Service errors - Database, Redis, etc.

## Configuration Options

### Categorization Options
```ruby
{
  use_cache: true,              # Enable caching
  check_user_preferences: true, # Check user prefs first
  include_alternatives: false,  # Include alternative categories
  min_confidence: 0.5,          # Minimum confidence threshold
  max_results: 10,              # Max patterns to evaluate
  max_categories: 5,            # Max categories to return
  auto_update: true,            # Auto-update expense
  skip_cache_preload: false     # Skip cache preload (batch)
}
```

## Usage Examples

### Basic Categorization
```ruby
engine = Categorization::Engine.instance
result = engine.categorize(expense)

if result.successful?
  puts "Category: #{result.category.name}"
  puts "Confidence: #{result.confidence}"
end
```

### Batch Processing
```ruby
results = engine.batch_categorize(expenses)
successful = results.select(&:successful?)
puts "Categorized #{successful.size} of #{results.size} expenses"
```

### Learning from Corrections
```ruby
engine.learn_from_correction(
  expense,
  correct_category,
  predicted_category
)
```

### Performance Monitoring
```ruby
metrics = engine.metrics
puts "Success rate: #{metrics[:engine][:success_rate]}%"
puts "Avg time: #{metrics[:performance][:categorizations][:avg_ms]}ms"
puts "Cache hit rate: #{metrics[:cache][:hit_rate]}%"
```

## Testing

### Integration Tests
Located in `spec/services/categorization/engine_spec.rb`

Key test scenarios:
- User preference prioritization
- Pattern matching with confidence
- Alternative category suggestions
- Auto-update behavior
- Performance targets
- Error handling
- Batch processing
- Learning feedback loop

### Performance Testing
```ruby
# Ensure <10ms target
results = 100.times.map { engine.categorize(expense) }
avg_time = results.sum(&:processing_time_ms) / results.size
expect(avg_time).to be < 10.0
```

## Future Enhancements

1. **Machine Learning Integration**: Neural network for pattern recognition
2. **Async Processing**: Background job queue for batch operations
3. **Distributed Caching**: Redis Cluster for horizontal scaling
4. **A/B Testing**: Multiple algorithms with performance comparison
5. **Real-time Learning**: Continuous pattern improvement
6. **Multi-tenant Support**: Per-user pattern isolation