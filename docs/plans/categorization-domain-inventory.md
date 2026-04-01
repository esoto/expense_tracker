# Categorization Domain - Complete Inventory

**Generated:** 2026-03-26
**Scope:** Every file, class, method, and test that touches categorization

---

## 1. Services

### 1.1 Core Services (`app/services/categorization/`)

| File | Class | Description | Spec Exists? |
|------|-------|-------------|:---:|
| `engine.rb` | `Services::Categorization::Engine` | Production-ready categorization engine with DI, thread-safe operations, circuit breakers, LRU caching, batch processing, and <10ms performance target. Main entry point for categorize/learn/batch operations. Also defines `SimpleCircuitBreaker` and error classes (`CategorizationError`, `DatabaseError`, `CacheError`, `ValidationError`, `CircuitOpenError`). | YES (`engine_spec.rb`, `engine_thread_pool_spec.rb`) |
| `orchestrator.rb` | `Services::Categorization::Orchestrator` | Clean orchestrator following SRP -- orchestrates categorization workflow with timeout protection, circuit breaker, parallel batch processing. Delegates all implementation to specialized services. Also defines inner `CircuitBreaker` class. | YES (`orchestrator_spec.rb`, `orchestrator_debug_spec.rb`, `orchestrator_improvements_spec.rb`, `orchestrator_integration_spec.rb`, `orchestrator_performance_spec.rb`, `orchestrator_summary_spec.rb`, `orchestrator_thread_safety_spec.rb`) |
| `pattern_learner.rb` | `Services::Categorization::PatternLearner` | ML-inspired learning from user corrections: pattern strengthening/weakening, creation, merging, and decay. Includes inner classes: `LearningResult`, `BatchLearningResult`, `DecayResult`, `PerformanceTracker`. | YES (`pattern_learner_spec.rb`, `pattern_learner_integration_spec.rb`) |
| `confidence_calculator.rb` | `Services::Categorization::ConfidenceCalculator` | Multi-factor confidence scoring combining text_match (35%), historical_success (25%), usage_frequency (15%), amount_similarity (15%), temporal_pattern (10%). Sigmoid normalization. Also defines `ConfidenceScore` value object. Inner `PerformanceTracker` class. | YES (`confidence_calculator_spec.rb`, `confidence_calculator_integration_spec.rb`) |
| `pattern_cache.rb` | `Services::Categorization::PatternCache` | Two-tier caching (Memory L1 + Redis L2) for patterns, composites, user preferences. <1ms lookups, cache warming, atomic version-key invalidation. Inner `MetricsCollector` class. | YES (`pattern_cache_spec.rb`, `pattern_cache_unit_spec.rb`) |
| `categorization_result.rb` | `Services::Categorization::CategorizationResult` | Value object for categorization results with confidence levels, alternatives, performance metrics, explanation generation. Factory methods: `no_match`, `from_user_preference`, `from_pattern_match`, `error`. | YES (`categorization_result_spec.rb`) |
| `learning_result.rb` | `Services::Categorization::LearningResult` | Value object for learning operation results tracking patterns created/updated, with factory methods `success` and `error`. | NO |
| `enhanced_categorization_service.rb` | `Services::Categorization::EnhancedCategorizationService` | Integrates fuzzy matching with pattern-based categorization. Tries user preferences, canonical merchants, pattern matching, then composite patterns. Includes category suggestion and feedback learning. | YES (`enhanced_categorization_service_spec.rb`) |
| `bulk_categorization_service.rb` | `Services::Categorization::BulkCategorizationService` | Consolidated bulk categorization: preview, apply, undo, export (CSV/JSON/XLSX), grouping (merchant/date/amount/category/similarity), auto-categorize, suggestions. Replaces 8 separate service files. | YES (`bulk_categorization_service_spec.rb`) |
| `engine_factory.rb` | `Services::Categorization::EngineFactory` | Factory for creating/managing Engine instances. Provides `default`, `create`, `get`, `reset!`, and `configure` class methods. Thread-safe with `Concurrent::Map`. | YES (`engine_factory_spec.rb`) |
| `orchestrator_factory.rb` | `Services::Categorization::OrchestratorFactory` | Factory for Orchestrator instances with environment-specific configs (production, test, development, custom, minimal). Also defines test doubles: `InMemoryPatternCache`, `SimpleMatcher`, `SimpleConfidenceCalculator`, `TestPatternLearner`, `NoOpPatternLearner`, `NoOpPerformanceTracker`, `TestCircuitBreaker`. | YES (`orchestrator_factory_spec.rb`) |
| `lru_cache.rb` | `Services::Categorization::LruCache` | Thread-safe LRU cache with TTL support using `concurrent-ruby`. Background cleanup thread for expired entries. Provides `fetch`, `get`, `set`, `delete`, `clear`, `stats`. | YES (`lru_cache_spec.rb`) |
| `ml_confidence_integration.rb` | `Services::Categorization::MlConfidenceIntegration` | Concern (module) that integrates ML confidence scores with expenses. Updates expense ML fields, builds confidence explanations (Spanish), handles accept/reject of ML suggestions with feedback tracking. | YES (`ml_confidence_integration_spec.rb`) |
| `service_registry.rb` | `Services::Categorization::ServiceRegistry` | DI container for categorization services. Provides `register`, `get`, `fetch`, `build_defaults`. Thread-safe with Mutex. | YES (`service_registry_spec.rb`) |
| `performance_tracker.rb` | `Services::Categorization::PerformanceTracker` | Thread-safe performance monitoring with percentiles, health states, optimization suggestions, error rate tracking. Target <10ms. Uses `concurrent-ruby` primitives. | NO |
| `expense_collection_adapter.rb` | `Services::Categorization::ExpenseCollectionAdapter` | Adapter wrapping Array or ActiveRecord::Relation to provide uniform interface (`find_each`, `in_batches`, `each`, `select`, `map`, etc.) for bulk categorization. | NO |

### 1.2 Matchers (`app/services/categorization/matchers/`)

| File | Class | Description | Spec Exists? |
|------|-------|-------------|:---:|
| `fuzzy_matcher.rb` | `Services::Categorization::Matchers::FuzzyMatcher` | High-performance fuzzy matching with Jaro-Winkler (native gem), Levenshtein, trigram, and phonetic algorithms. Spanish character normalization, noise pattern removal, word-based matching, caching. Inner classes: `TextNormalizer`, `MetricsCollector`. | YES (`fuzzy_matcher_spec.rb`, `fuzzy_matcher_fixes_spec.rb`, `fuzzy_matcher_performance_spec.rb`) |
| `match_result.rb` | `Services::Categorization::Matchers::MatchResult` | Value object for fuzzy match results. Filtering (`above_threshold`, `top`), confidence levels, pattern/merchant accessors, merge support, enumerable interface. Factory methods: `empty`, `timeout`, `error`. | YES (`match_result_spec.rb`) |
| `text_extractor.rb` | `Services::Categorization::Matchers::TextExtractor` | Extracts text from various object types (String, Hash, CategorizationPattern, Expense, CanonicalMerchant, MerchantAlias, generic). Used by FuzzyMatcher for candidate text extraction. | YES (`text_extractor_spec.rb`) |

### 1.3 Monitoring (`app/services/categorization/monitoring/`)

| File | Class | Description | Spec Exists? |
|------|-------|-------------|:---:|
| `health_check.rb` | `Services::Categorization::Monitoring::HealthCheck` | Health checks for database, Redis, pattern counts, success rates, error rates, cache hit rates with configurable thresholds. | YES (`health_check_spec.rb`) |
| `metrics_collector.rb` | `Services::Categorization::Monitoring::MetricsCollector` | Singleton metrics collector with StatsD integration, confidence buckets, thread-safe operations. | NO (no dedicated spec; tested via integration) |
| `structured_logger.rb` | `Services::Categorization::Monitoring::StructuredLogger` | JSON-formatted structured logging with correlation IDs, sensitive field redaction, categorization event logging. | YES (`structured_logger_spec.rb`) |
| `data_quality_checker.rb` | `Services::Categorization::Monitoring::DataQualityChecker` | Pattern data quality auditing: coverage ratio, success rates, diversity score, freshness, duplicate detection. Weighted quality scoring. | YES (`data_quality_checker_spec.rb`) |
| `engine_integration.rb` | `Services::Categorization::Monitoring::EngineIntegration` | Concern that monkey-patches Engine methods with monitoring wrappers for categorize and learn_from_correction. | NO |
| `dashboard_adapter.rb` | `Services::Categorization::Monitoring::DashboardAdapter` | Strategy adapter switching between original and optimized dashboard helper implementations. Configurable via env var or Rails config. | YES (`dashboard_adapter_spec.rb`) |
| `dashboard_helper.rb` | `Services::Categorization::Monitoring::DashboardHelper` | Module providing dashboard metrics summary: categorization, patterns, cache, performance, learning, system metrics. | YES (`dashboard_helper_spec.rb`) |
| `dashboard_helper_optimized.rb` | `Services::Categorization::Monitoring::DashboardHelperOptimized` | Optimized version of DashboardHelper with 10-second cache TTL to reduce database load. | YES (`dashboard_helper_optimized_spec.rb`) |

### 1.4 Root-Level Services

| File | Class | Description | Spec Exists? |
|------|-------|-------------|:---:|
| `app/services/categorization_service.rb` | `Services::CategorizationService` | Original/legacy categorization service. Checks user preferences, pattern matches, composite matches, combines scores. Includes `record_feedback`, `suggest_new_patterns`, `pattern_performance_report`. | YES (`categorization_service_spec.rb`) |
| `app/services/bulk_operations/categorization_service.rb` | `Services::BulkOperations::CategorizationService` | Bulk operations service extending `BaseService`. Uses `update_all` for performance, tracks ML corrections, broadcasts updates via ActionCable. Falls back to individual updates on failure. | NO (no dedicated spec) |

---

## 2. Models

### 2.1 `CategorizationPattern` (`app/models/categorization_pattern.rb`)

**Purpose:** Pattern-based rule for automatically categorizing expenses (merchant, keyword, description, amount_range, regex, time).

**Associations:**
- `belongs_to :category`
- `has_many :pattern_feedbacks, dependent: :destroy`
- `has_many :expenses, through: :pattern_feedbacks`

**Validations:**
- `pattern_type` -- presence, inclusion in `PATTERN_TYPES`
- `pattern_value` -- presence, uniqueness scoped to `[category_id, pattern_type]`
- `confidence_weight` -- numericality 0.1..5.0
- `usage_count` -- >= 0
- `success_count` -- >= 0, not greater than `usage_count`
- `success_rate` -- 0.0..1.0
- Custom: `validate_pattern_value_format` (amount_range, regex, time format)

**Key Scopes:** `active`, `inactive`, `user_created`, `system_created`, `by_type`, `high_confidence`, `successful`, `frequently_used`, `ordered_by_success`, `with_category`, `with_statistics`, `for_matching`

**Key Methods:** `record_usage(was_successful)`, `matches?(text_or_options)`, `effective_confidence`, `check_and_deactivate_if_poor_performance`

**Concerns:** `PatternValidation` (`app/models/concerns/pattern_validation.rb`)

**Specs:** YES (`categorization_pattern_spec.rb`, `categorization_pattern_unit_spec.rb`, `categorization_pattern_edge_cases_spec.rb`, `categorization_pattern_fixes_spec.rb`, `categorization_models_integration_spec.rb`)

### 2.2 `CompositePattern` (`app/models/composite_pattern.rb`)

**Purpose:** Complex categorization rules combining multiple CategorizationPatterns with AND/OR/NOT operators and additional conditions (amount, time, day-of-week, merchant blacklist).

**Associations:**
- `belongs_to :category`

**Validations:**
- `name` -- presence, uniqueness scoped to `category_id`
- `operator` -- presence, inclusion in `%w[AND OR NOT]`
- `pattern_ids` -- presence, existence check, same-category check
- `confidence_weight` -- 0.1..5.0
- `usage_count`, `success_count`, `success_rate` -- numeric constraints
- Custom: `validate_conditions_format`

**Key Methods:** `component_patterns`, `matches?(expense)`, `record_usage(was_successful)`, `effective_confidence`, `add_pattern`, `remove_pattern`, `description`

**Specs:** YES (`composite_pattern_spec.rb`, `composite_pattern_unit_spec.rb`)

### 2.3 `Category` (`app/models/category.rb`)

**Purpose:** Expense category with parent-child hierarchy.

**Associations:**
- `belongs_to :parent` (self-referential, optional)
- `has_many :children`
- `has_many :expenses`
- `has_many :categorization_patterns`
- `has_many :composite_patterns`
- `has_many :pattern_feedbacks`
- `has_many :pattern_learning_events`
- `has_many :user_category_preferences`

**Key Scopes:** `root_categories`, `subcategories`, `active`

**Key Methods:** `root?`, `subcategory?`, `full_name`

**Specs:** YES (`category_spec.rb`, `category_unit_spec.rb`)

### 2.4 `UserCategoryPreference` (`app/models/user_category_preference.rb`)

**Purpose:** Stores learned user preferences for categorization by merchant, time, day, and amount context.

**Associations:**
- `belongs_to :email_account`
- `belongs_to :category`

**Context Types:** `merchant`, `time_of_day`, `day_of_week`, `amount_range`

**Key Class Methods:** `learn_from_categorization`, `matching_preferences`, `learn_preference`

**Specs:** YES (`user_category_preference_unit_spec.rb`)

### 2.5 `CanonicalMerchant` (`app/models/canonical_merchant.rb`)

**Purpose:** Normalized canonical merchant names. Groups raw merchant strings (e.g., "UBER *TRIP" -> "uber") using fuzzy matching (pg_trgm).

**Associations:**
- `has_many :merchant_aliases`

**Key Class Methods:** `find_or_create_from_raw`, `normalize_merchant_name`, `beautify_merchant_name`, `find_similar_canonical`, `calculate_similarity_confidence`

**Key Instance Methods:** `record_usage`, `all_raw_names`, `most_common_raw_name`, `merge_with`, `suggest_category`

**Specs:** YES (`canonical_merchant_unit_spec.rb`)

### 2.6 `PatternFeedback` (`app/models/pattern_feedback.rb`)

**Purpose:** Records user feedback on categorization suggestions (accepted/rejected/corrected/correction). Auto-creates new patterns from corrections.

**Associations:**
- `belongs_to :categorization_pattern` (optional)
- `belongs_to :expense`
- `belongs_to :category`

**Feedback Types:** `accepted`, `rejected`, `corrected`, `correction`

**Key Methods:** `self.record_feedback`, `successful?`, `improvement_suggestion`

**Callbacks:** `update_pattern_performance`, `create_pattern_from_correction` (on correction), `invalidate_analytics_cache`

**Specs:** YES (`pattern_feedback_spec.rb`, `pattern_feedback_unit_spec.rb`)

### 2.7 `PatternLearningEvent` (`app/models/pattern_learning_event.rb`)

**Purpose:** Audit trail for categorization learning events, tracking which patterns were used and correctness.

**Associations:**
- `belongs_to :expense`
- `belongs_to :category`

**Key Methods:** `self.record_event`, `successful?`

**Specs:** YES (`pattern_learning_event_unit_spec.rb`)

### 2.8 Related Concern

| File | Module | Description | Spec Exists? |
|------|--------|-------------|:---:|
| `app/models/concerns/pattern_validation.rb` | `PatternValidation` | Shared validation logic included in `CategorizationPattern` | YES (`pattern_validation_spec.rb`, `pattern_validation_unit_spec.rb`) |

---

## 3. Controllers

### 3.1 Main App Controllers

| File | Class | Actions | Description | Spec Exists? |
|------|-------|---------|-------------|:---:|
| `expenses_controller.rb` | `ExpensesController` | `correct_category`, `accept_suggestion`, `reject_suggestion` | Inline categorization actions: correct a category (with learning), accept/reject ML suggestions | YES (partially -- `expenses_controller_confidence_spec.rb`) |
| `categories_controller.rb` | `CategoriesController` | `index` | Lists categories as JSON for dropdowns | YES (`category_spec.rb` covers model) |
| `bulk_categorizations_controller.rb` | `BulkCategorizationsController` | `index`, `show` | Displays grouped uncategorized expenses for bulk categorization UI | YES (`bulk_categorizations_controller_spec.rb`) |
| `bulk_categorization_actions_controller.rb` | `BulkCategorizationActionsController` | `categorize`, `suggest`, `preview`, `auto_categorize`, `undo`, `export` | Executes bulk categorization operations via `BulkCategorizationService` | YES (`bulk_categorization_actions_controller_unit_spec.rb`, `bulk_categorization_actions_controller_security_spec.rb`) |

### 3.2 Admin Controllers

| File | Class | Actions | Description | Spec Exists? |
|------|-------|---------|-------------|:---:|
| `admin/patterns_controller.rb` | `Admin::PatternsController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`, `toggle_active`, `test_single`, `test_pattern`, `statistics`, `performance`, `import`, `export` | Full CRUD + testing, stats, import/export for CategorizationPatterns | YES (`admin/patterns_controller_spec.rb`) |
| `admin/composite_patterns_controller.rb` | `Admin::CompositePatternsController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`, `toggle_active`, `test` | Full CRUD + testing for CompositePatterns | YES (`admin/composite_patterns_controller_unit_spec.rb`) |
| `admin/pattern_management_controller.rb` | `Admin::PatternManagementController` | `import`, `export`, `analytics` | Pattern import (CSV), export, analytics operations | YES (`admin/pattern_management_controller_unit_spec.rb`) |
| `admin/pattern_testing_controller.rb` | `Admin::PatternTestingController` | `test`, `test_pattern` | Interactive pattern testing against sample expenses | YES (`admin/pattern_testing_controller_unit_spec.rb`) |

### 3.3 API Controllers

| File | Class | Actions | Description | Spec Exists? |
|------|-------|---------|-------------|:---:|
| `api/v1/categorization_controller.rb` | `Api::V1::CategorizationController` | `suggest`, `feedback`, `correct_category`, `accept_suggestion`, `reject_suggestion` | API endpoints for categorization suggestions, feedback, and corrections | YES (`api/v1/categorization_spec.rb`, `api/v1/categorization_controller_unit_spec.rb`) |
| `api/v1/patterns_controller.rb` | `Api::V1::PatternsController` | `index`, `show`, `create`, `update`, `destroy` | REST API for pattern CRUD with filtering, sorting, pagination | YES (`api/v1/patterns_spec.rb`, `api/v1/patterns_security_spec.rb`, `api/v1/patterns_performance_spec.rb`, `api/v1/patterns_controller_unit_spec.rb`) |
| `api/v1/categories_controller.rb` | `Api::V1::CategoriesController` | `index` | API endpoint listing all categories | YES (covered in request specs) |

### 3.4 Analytics Controllers

| File | Class | Actions | Description | Spec Exists? |
|------|-------|---------|-------------|:---:|
| `analytics/pattern_dashboard_controller.rb` | `Analytics::PatternDashboardController` | `index`, `export`, `chart_data`, `heatmap_data`, `trend_data` | Pattern analytics dashboard with cached metrics, chart data, export. Defines `ANALYTICS_VERSION_KEY` for atomic cache invalidation. | YES (`analytics/pattern_dashboard_controller_spec.rb`) |

---

## 4. Background Jobs

| File | Class | Queue | Description | Spec Exists? |
|------|-------|-------|-------------|:---:|
| `app/jobs/bulk_categorization_job.rb` | `BulkCategorizationJob` | `bulk_operations` | Processes bulk categorizations in batches of 20 (max 100 per job). Retries on deadlock/not-found. Broadcasts completion/failure via Turbo Streams. | YES (`bulk_categorization_job_spec.rb`) |

---

## 5. Stimulus Controllers (JavaScript)

### 5.1 Categorization-Specific

| File | Controller Name | Description |
|------|----------------|-------------|
| `category_confidence_controller.js` | `category-confidence` | Displays ML confidence badges with tooltips, correction panel for category changes, keyboard shortcuts (C to correct), touch interactions |
| `bulk_categorization_controller.js` | `bulk-categorization` | Manages bulk categorization UI: expense group selection, category dropdown per group, expand/collapse expense lists |

### 5.2 Inline Actions (Categorization-Related)

| File | Controller Name | Description |
|------|----------------|-------------|
| `inline_actions_controller.js` | `inline-actions` | Full inline actions for expenses: category dropdown, delete confirmation, status toggle, duplicate button, keyboard shortcuts, undo notifications |
| `dashboard_inline_actions_controller.js` | `dashboard-inline-actions` | Dashboard-specific inline actions for quick categorize, status toggle, duplicate, delete |
| `simple_inline_actions_controller.js` | `simple-inline-actions` | Simplified hover-based show/hide for inline action containers |

### 5.3 Pattern Management (Admin)

| File | Controller Name | Description |
|------|----------------|-------------|
| `pattern_form_controller.js` | `pattern-form` | Dynamic pattern form: updates help text based on pattern type, inline pattern testing |
| `pattern_management_controller.js` | `pattern-management` | Pattern management UI: import modal, search with debounce, keyboard shortcuts |
| `pattern_chart_controller.js` | `pattern-chart` | Chart.js line/bar charts for pattern performance analytics |
| `pattern_heatmap_controller.js` | `pattern-heatmap` | Heatmap visualization for pattern usage data |
| `pattern_trend_chart_controller.js` | `pattern-trend-chart` | Trend charts with daily/weekly/monthly interval switching |
| `pattern_analytics_filters_controller.js` | `pattern-analytics-filters` | Filter controls for analytics dashboard (time period, category, pattern type) |
| `pattern_test_example_controller.js` | `pattern-test-example` | Fills pattern test form with example data from predefined test cases |

### 5.4 Related Bulk Operations

| File | Controller Name | Description |
|------|----------------|-------------|
| `bulk_actions_controller.js` | `bulk-actions` | General bulk actions (select all, apply action) -- used for batch categorization selection |
| `bulk_operations_controller.js` | `bulk-operations` | Bulk operations orchestration and progress tracking |

---

## 6. Test Coverage Summary

### 6.1 Services with Specs

| Service | Spec Files |
|---------|-----------|
| Engine | `engine_spec.rb`, `engine_thread_pool_spec.rb` |
| Orchestrator | `orchestrator_spec.rb`, `orchestrator_debug_spec.rb`, `orchestrator_improvements_spec.rb`, `orchestrator_integration_spec.rb`, `orchestrator_performance_spec.rb`, `orchestrator_summary_spec.rb`, `orchestrator_thread_safety_spec.rb` |
| PatternLearner | `pattern_learner_spec.rb`, `pattern_learner_integration_spec.rb` |
| ConfidenceCalculator | `confidence_calculator_spec.rb`, `confidence_calculator_integration_spec.rb` |
| PatternCache | `pattern_cache_spec.rb`, `pattern_cache_unit_spec.rb` |
| CategorizationResult | `categorization_result_spec.rb` |
| EnhancedCategorizationService | `enhanced_categorization_service_spec.rb` |
| BulkCategorizationService | `bulk_categorization_service_spec.rb` |
| EngineFactory | `engine_factory_spec.rb` |
| OrchestratorFactory | `orchestrator_factory_spec.rb` |
| LruCache | `lru_cache_spec.rb` |
| MlConfidenceIntegration | `ml_confidence_integration_spec.rb` |
| ServiceRegistry | `service_registry_spec.rb` |
| FuzzyMatcher | `fuzzy_matcher_spec.rb`, `fuzzy_matcher_fixes_spec.rb`, `fuzzy_matcher_performance_spec.rb` |
| MatchResult | `match_result_spec.rb` |
| TextExtractor | `text_extractor_spec.rb` |
| CategorizationService (legacy) | `categorization_service_spec.rb` |
| HealthCheck | `health_check_spec.rb` |
| StructuredLogger | `structured_logger_spec.rb` |
| DataQualityChecker | `data_quality_checker_spec.rb` |
| DashboardAdapter | `dashboard_adapter_spec.rb` |
| DashboardHelper | `dashboard_helper_spec.rb` |
| DashboardHelperOptimized | `dashboard_helper_optimized_spec.rb` |
| PatternPerformanceAnalyzer | `pattern_performance_analyzer_spec.rb`, `pattern_performance_analyzer_security_spec.rb` |

### 6.2 Services WITHOUT Specs (Gaps)

| Service | File |
|---------|------|
| `LearningResult` | `app/services/categorization/learning_result.rb` |
| `PerformanceTracker` | `app/services/categorization/performance_tracker.rb` |
| `ExpenseCollectionAdapter` | `app/services/categorization/expense_collection_adapter.rb` |
| `BulkOperations::CategorizationService` | `app/services/bulk_operations/categorization_service.rb` |
| `Monitoring::MetricsCollector` | `app/services/categorization/monitoring/metrics_collector.rb` |
| `Monitoring::EngineIntegration` | `app/services/categorization/monitoring/engine_integration.rb` |

### 6.3 Integration/Cross-Cutting Specs

| Spec File | Coverage |
|-----------|----------|
| `spec/integration/ml_confidence_categorization_spec.rb` | End-to-end ML confidence flow |
| `spec/models/categorization_models_integration_spec.rb` | Cross-model integration |

### 6.4 Support Files

| File | Purpose |
|------|---------|
| `spec/support/categorization_helper.rb` | Shared test helpers for categorization specs |
| `spec/factories/categorization_patterns.rb` | FactoryBot factory |
| `spec/factories/composite_patterns.rb` | FactoryBot factory |
| `spec/factories/pattern_feedbacks.rb` | FactoryBot factory |
| `spec/factories/pattern_learning_events.rb` | FactoryBot factory |
| `spec/factories/user_category_preferences.rb` | FactoryBot factory |
| `spec/factories/canonical_merchants.rb` | FactoryBot factory |
| `spec/factories/expenses_ml_confidence.rb` | FactoryBot trait/factory for ML fields |
| `spec/fixtures/files/patterns.csv` | CSV fixture for import tests |

---

## 7. Documentation

No categorization-specific plan documents found in `docs/plans/`. The categorization domain is documented inline via:

- `CLAUDE.md` -- Service architecture section describes categorization domain organization
- Code-level documentation (YARD-style comments in all service classes)
- `docs/plans/qa-playbook-group-cd-bulk-email-sync.md` -- QA scenarios touching bulk categorization

---

## 8. File Count Summary

| Category | Count |
|----------|------:|
| Services (Ruby) | 27 files |
| Models | 7 files + 1 concern |
| Controllers | 11 files |
| Background Jobs | 1 file |
| Stimulus Controllers (JS) | 12 files |
| Spec Files | 65+ files |
| Factories | 6 files |
| **Total Files** | **~130** |

---

## 9. Architecture Diagram (Text)

```
                    ExpensesController
                    (correct_category, accept/reject_suggestion)
                           |
          +----------------+----------------+
          |                                 |
    CategorizationService             Api::V1::CategorizationController
    (legacy, simple)                  (suggest, feedback)
          |                                 |
          +----------- OR -----------------+
                       |
         +-------------+-------------+
         |                           |
    Engine                    Orchestrator
    (DI, circuit breakers,    (SRP workflow,
     thread pool, batch)       timeout protection)
         |                           |
         +------ both use ----------+
                    |
    +------+--------+--------+--------+
    |      |        |        |        |
 Pattern  Fuzzy   Confidence Pattern  Performance
  Cache   Matcher Calculator Learner  Tracker
    |      |        |        |
    |   TextExtractor     PatternFeedback
    |   MatchResult       PatternLearningEvent
    |                     LearningResult
    +-- CategorizationPattern
    +-- CompositePattern
    +-- UserCategoryPreference
    +-- CanonicalMerchant

    Monitoring Layer:
    HealthCheck | MetricsCollector | StructuredLogger
    DataQualityChecker | DashboardHelper(Optimized)
    EngineIntegration | DashboardAdapter

    Bulk Operations:
    BulkCategorizationService (preview/apply/undo/export/suggest)
    BulkOperations::CategorizationService (update_all)
    BulkCategorizationJob (async, Solid Queue)
    BulkCategorizationsController + BulkCategorizationActionsController

    Admin:
    PatternsController | CompositePatternsController
    PatternManagementController | PatternTestingController
    Analytics::PatternDashboardController

    JS (Stimulus):
    category-confidence | bulk-categorization | inline-actions
    pattern-form | pattern-management | pattern-chart
    pattern-heatmap | pattern-trend-chart | pattern-analytics-filters
```
