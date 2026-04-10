# Categorization Phase 2: Intelligent Layered Categorization

**Date:** 2026-04-10
**Status:** Approved
**Scope:** Single-user architecture (multi-tenant wraps around later)

## Overview

Extend the existing pattern-based categorization (Phase 1) with two new layers: PostgreSQL-native similarity matching and Claude Haiku LLM fallback. Replaces the original Phase 2 (Naive Bayes) and Phase 3 (Hybrid AI) plans with a pragmatic, lower-complexity approach.

## Architecture

```
Expense arrives
    |
+----------------------------------+
|  Layer 1: Pattern Matching        |  <10ms, $0
|  (existing Engine + FuzzyMatcher) |
|  Confidence >= 70%? -> Done       |
+----------------+-----------------+
                 | < 70%
                 v
+----------------------------------+
|  Layer 2: pg_trgm Similarity      |  ~50ms, $0
|  TF-IDF vectors in PostgreSQL     |
|  Confidence >= 70%? -> Done       |
+----------------+-----------------+
                 | < 70%
                 v
+----------------------------------+
|  Layer 3: Claude Haiku            |  ~1-2s, ~$0.001
|  Cached by merchant name          |
|  Returns leaf category            |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
|  Learning Loop                    |
|  Result -> PatternLearner         |
|  3-strike escalation on bad maps  |
|  Metrics logged for every call    |
+----------------------------------+
```

**Key rules:**
- Each layer only fires if the previous one returned confidence < 70%
- Layer 3 results are cached -- same merchant never calls Haiku twice unless invalidated by three-strike escalation
- All three layers return the same `CategorizationResult` value object (already exists)
- Entry point: the existing `Categorization::Engine`, extended with strategy classes

## Layer 2: pg_trgm Similarity Engine

### New table: `categorization_vectors`

```ruby
create_table :categorization_vectors do |t|
  t.string :merchant_normalized, null: false
  t.references :category, foreign_key: true, null: false
  t.integer :occurrence_count, default: 1
  t.integer :correction_count, default: 0
  t.float :confidence, default: 0.5
  t.string :description_keywords, array: true, default: []
  t.datetime :last_seen_at
  t.timestamps

  t.index :merchant_normalized, using: :gist, opclass: :gist_trgm_ops
  t.index [:merchant_normalized, :category_id], unique: true
end
```

### Matching logic

1. Normalize incoming expense merchant name (lowercase, strip whitespace/special chars)
2. Query: `SELECT * FROM categorization_vectors WHERE similarity(merchant_normalized, ?) > 0.3 ORDER BY similarity DESC LIMIT 5`
3. Top result similarity > 0.6 AND occurrence_count > 2 -> high confidence match
4. Multiple categories match same merchant with similar scores -> low confidence, fall through to Layer 3
5. Keywords array as tiebreaker -- if similarity scores are close, check description word overlap

### Learning

- Every confirmed categorization (user accepts or doesn't correct within 24h) -> upsert into `categorization_vectors`, increment `occurrence_count`
- Every correction (at any time, even weeks later) -> immediately update category, increment `correction_count`, overwrite any prior positive signal
- `correction_count >= 3` in 30 days -> confidence drops below threshold, triggers Haiku re-evaluation

## Layer 3: Claude Haiku Fallback

### New table: `llm_categorization_cache`

```ruby
create_table :llm_categorization_cache do |t|
  t.string :merchant_normalized, null: false
  t.references :category, foreign_key: true, null: false
  t.float :confidence
  t.string :model_used, default: "claude-haiku-4-5"
  t.integer :token_count
  t.decimal :cost, precision: 10, scale: 6
  t.datetime :expires_at
  t.timestamps

  t.index :merchant_normalized, unique: true
  t.index :expires_at
end
```

### Prompt

```
You are an expense categorizer. Given an expense, return the single best
matching category from the list below. Return ONLY the category key,
nothing else.

Categories:
- food, restaurants, supermarket, coffee_shop
- transport, gas, rideshare, bus
- utilities, electricity, water, internet, phone
- entertainment
- health
- shopping, clothing, electronics, household
- education
- home
- uncategorized

Expense:
Merchant: {merchant}
Description: {description}
Amount: {amount} {currency}
```

### Cache behavior

- 90-day TTL, refreshed on each hit (active merchants stay cached indefinitely)
- Cache miss -> call Haiku, store result, feed into Layer 2 learning loop
- Three-strike invalidation: delete cache entry, re-call with correction history appended

### Cost control

- Monthly budget cap: $5/month. Exceeding cap -> Layer 3 returns `uncategorized` with low confidence
- Budget tracked via counter in `Rails.cache`

## Metrics & Monitoring

### New table: `categorization_metrics`

```ruby
create_table :categorization_metrics do |t|
  t.references :expense, foreign_key: true, null: false
  t.string :layer_used, null: false
  t.float :confidence
  t.references :category, foreign_key: true
  t.boolean :was_corrected, default: false
  t.references :corrected_to_category, foreign_key: { to_table: :categories }
  t.integer :time_to_correction_hours
  t.float :processing_time_ms
  t.decimal :api_cost, precision: 10, scale: 6, default: 0
  t.timestamps

  t.index :layer_used
  t.index :was_corrected
  t.index :created_at
end
```

### Admin dashboard (`/admin/categorization_metrics`)

Three sections:

1. **Overview Cards** -- overall accuracy (30 days), LLM fallback rate, user correction rate, API spend vs $5 budget
2. **Layer Performance Table** -- per-layer total/correct/corrected/accuracy/avg confidence/avg time
3. **Problem Merchants** -- three-strike watchlist with correction counts and links to filtered expense list

### Weekly summary job

Computes per-layer accuracy, fallback rate, correction rate, API spend. Logs warnings for ONNX evaluation triggers:
- LLM fallback rate > 15% for 3 consecutive weeks
- User correction rate > 10% for 3 consecutive weeks
- Both sustained for 12 weeks -> log recommendation to evaluate ONNX

## Integration with Existing Engine

### New service classes

```
app/services/categorization/
  engine.rb                          # modified to chain strategies
  strategies/
    pattern_strategy.rb              # wraps existing FuzzyMatcher (Layer 1)
    similarity_strategy.rb           # pg_trgm queries (Layer 2)
    llm_strategy.rb                  # Haiku fallback (Layer 3)
  llm/
    client.rb                        # Anthropic API wrapper
    prompt_builder.rb                # builds categorization prompt
    response_parser.rb               # parses Haiku response -> category
  learning/
    vector_updater.rb                # updates categorization_vectors
    correction_handler.rb            # user corrections + three-strike
    metrics_recorder.rb              # logs to categorization_metrics
  monitoring/
    metrics_dashboard_service.rb     # queries for admin dashboard
```

### Engine modification

Strategy chain replaces current `perform_categorization`:

```ruby
def perform_categorization(expense)
  strategies.each do |strategy|
    result = strategy.call(expense)
    if result.confidence >= confidence_threshold
      record_metric(expense, result, strategy.layer_name)
      learn_from_result(expense, result)
      return result
    end
  end
  # All strategies below threshold -> return best result as "low confidence"
end
```

### Background jobs (Solid Queue)

- `CategorizationLearningJob` -- daily, processes 24h+ uncorrected expenses into learning loop
- `CategorizationMetricsSummaryJob` -- weekly, computes summary stats
- `StaleVectorCleanupJob` -- monthly, removes merchants not seen in 6+ months
- `LlmCacheCleanupJob` -- monthly, removes expired cache entries

## Implementation Tickets

### Phase A: Foundation

| Ticket | Description | Agent |
|--------|-------------|-------|
| A1 | Migrations: create `categorization_metrics`, `categorization_vectors`, `llm_categorization_cache` tables | Haiku |
| A2 | Strategy pattern refactor: extract `PatternStrategy` from Engine, introduce strategy chain | Sonnet |
| A3 | MetricsRecorder: log every categorization, wire into Engine | Haiku |
| A4 | Admin metrics dashboard: controller, view, MetricsDashboardService (overview cards + layer table) | Sonnet |

### Phase B: Layer 2

| Ticket | Description | Agent |
|--------|-------------|-------|
| B1 | SimilarityStrategy: pg_trgm query logic + tests | Haiku |
| B2 | VectorUpdater + backfill: populate categorization_vectors from historical data | Haiku |
| B3 | CorrectionHandler: three-strike logic, confidence decay, wire into correction flow | Haiku |
| B4 | Learning job: CategorizationLearningJob (daily) + StaleVectorCleanupJob (monthly) | Haiku |
| B5 | Problem Merchants UI: admin dashboard section with three-strike watchlist | Haiku |

### Phase C: Layer 3

| Ticket | Description | Agent |
|--------|-------------|-------|
| C1 | Anthropic client + prompt: llm/client.rb, prompt_builder.rb, response_parser.rb | Haiku |
| C2 | LlmStrategy + cache: strategy class, cache lookup/store, wire into Engine chain | Sonnet |
| C3 | Budget cap + escalation: monthly spend enforcement, three-strike cache invalidation | Haiku |
| C4 | Admin spend UI + cleanup job: API spend card, LlmCacheCleanupJob | Haiku |
| C5 | Weekly summary job: CategorizationMetricsSummaryJob + ONNX trigger warnings | Haiku |

## Future Considerations (Not Building Now)

- **ONNX Runtime**: Evaluate if pg_trgm accuracy insufficient after 3 months of data
- **Multi-tenant**: Per-user pattern isolation when PER-149 lands
- **Shared base model**: Global model + per-user overrides when user count justifies it
- **Vector embeddings (pgvector)**: Semantic similarity if pg_trgm text matching proves too literal
