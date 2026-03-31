# Categorization Domain -- Test Coverage Analysis

**Date**: 2026-03-26
**Scope**: All categorization-related source files and specs

## Summary

| Metric                     | Value   |
|----------------------------|---------|
| Total source files         | 46      |
| Files with specs           | 35      |
| Files without specs        | 11      |
| Coverage rate              | 76.1%   |
| Total test examples (unit) | 1,147   |
| Pending/skipped examples   | 36      |
| Pass/fail status           | **ALL PASS** (0 failures) |
| Suite run time             | 22.24s  |

---

## 1. Services: `app/services/categorization/` Cross-Reference

### Core Services

| Service File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `categorization_result.rb` | `categorization_result_spec.rb` | YES | 77 |
| `confidence_calculator.rb` | `confidence_calculator_spec.rb`, `confidence_calculator_integration_spec.rb` | YES | 55 + 11 = 66 |
| `engine.rb` | `engine_spec.rb`, `engine_thread_pool_spec.rb` | YES | 34 + 8 = 42 |
| `engine_factory.rb` | `engine_factory_spec.rb` | YES | 50 |
| `enhanced_categorization_service.rb` | `enhanced_categorization_service_spec.rb` | YES | 29 |
| `bulk_categorization_service.rb` | `bulk_categorization_service_spec.rb` | YES | 45 |
| `orchestrator.rb` | `orchestrator_spec.rb`, `orchestrator_integration_spec.rb`, `orchestrator_improvements_spec.rb`, `orchestrator_performance_spec.rb`, `orchestrator_thread_safety_spec.rb`, `orchestrator_summary_spec.rb`, `orchestrator_debug_spec.rb` | YES | 32+19+16+10+13+16+1 = 107 |
| `orchestrator_factory.rb` | `orchestrator_factory_spec.rb` | YES | 23 |
| `pattern_cache.rb` | `pattern_cache_spec.rb`, `pattern_cache_unit_spec.rb` | YES | 36 + 13 = 49 |
| `pattern_learner.rb` | `pattern_learner_spec.rb`, `pattern_learner_integration_spec.rb` | YES | 37 + 9 = 46 |
| `lru_cache.rb` | `lru_cache_spec.rb` | YES | 75 |
| `ml_confidence_integration.rb` | `ml_confidence_integration_spec.rb` | YES | 10 |
| `service_registry.rb` | `service_registry_spec.rb` | YES | 64 |
| `expense_collection_adapter.rb` | -- | **NO** | 0 |
| `learning_result.rb` | -- | **NO** | 0 |
| `performance_tracker.rb` | -- | **NO** | 0 |

### Matchers

| Service File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `matchers/fuzzy_matcher.rb` | `matchers/fuzzy_matcher_spec.rb`, `matchers/fuzzy_matcher_fixes_spec.rb`, `matchers/fuzzy_matcher_performance_spec.rb` | YES | 47+16+17 = 80 |
| `matchers/match_result.rb` | `matchers/match_result_spec.rb` | YES | 57 |
| `matchers/text_extractor.rb` | `matchers/text_extractor_spec.rb` | YES | 60 |

### Monitoring

| Service File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `monitoring/dashboard_adapter.rb` | `monitoring/dashboard_adapter_spec.rb` | YES | 28 |
| `monitoring/dashboard_helper.rb` | `monitoring/dashboard_helper_spec.rb` | YES | 37 |
| `monitoring/dashboard_helper_optimized.rb` | `monitoring/dashboard_helper_optimized_spec.rb` | YES | 34 (all 34 skipped -- stale) |
| `monitoring/data_quality_checker.rb` | `monitoring/data_quality_checker_spec.rb` | YES | 36 |
| `monitoring/health_check.rb` | `monitoring/health_check_spec.rb` | YES | 16 |
| `monitoring/structured_logger.rb` | `monitoring/structured_logger_spec.rb` | YES | 13 |
| `monitoring/engine_integration.rb` | -- | **NO** | 0 |
| `monitoring/metrics_collector.rb` | -- | **NO** | 0 |

### Root-level Categorization Service

| Service File | Spec File | Has Spec? | Example Count |
|---|---|---|---|
| `categorization_service.rb` | `categorization_service_spec.rb` | YES | 23 |

### Spec-only files (no matching source -- extra coverage)

| Spec File | Example Count | Notes |
|---|---|---|
| `circuit_breaker_spec.rb` | 18 | Tests circuit breaker behavior (may be inline in another service) |

---

## 2. Models Cross-Reference

| Model File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `categorization_pattern.rb` | `categorization_pattern_spec.rb`, `categorization_pattern_unit_spec.rb`, `categorization_pattern_fixes_spec.rb`, `categorization_pattern_edge_cases_spec.rb`, `categorization_models_integration_spec.rb` | YES | 55+108+28+26+6 = 223 |
| `composite_pattern.rb` | `composite_pattern_spec.rb`, `composite_pattern_unit_spec.rb` | YES | 35+65 = 100 |
| `category.rb` | `category_spec.rb`, `category_unit_spec.rb` | YES | 18+28 = 46 |
| `canonical_merchant.rb` | `canonical_merchant_unit_spec.rb` | YES | 66 |

All categorization models have specs. **No gaps.**

---

## 3. Controllers Cross-Reference

| Controller File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `admin/patterns_controller.rb` | `admin/patterns_controller_spec.rb` | YES | 110 |
| `admin/pattern_testing_controller.rb` | `admin/pattern_testing_controller_unit_spec.rb` | YES | 15 |
| `admin/pattern_management_controller.rb` | `admin/pattern_management_controller_unit_spec.rb` | YES | 28 |
| `admin/composite_patterns_controller.rb` | `admin/composite_patterns_controller_unit_spec.rb` | YES | 22 |
| `analytics/pattern_dashboard_controller.rb` | `analytics/pattern_dashboard_controller_spec.rb` | YES | 71 |
| `bulk_categorizations_controller.rb` | `bulk_categorizations_controller_spec.rb` | YES | 30 |
| `bulk_categorization_actions_controller.rb` | `bulk_categorization_actions_controller_unit_spec.rb`, `bulk_categorization_actions_controller_security_spec.rb` | YES | 30+17 = 47 |
| `api/v1/categorization_controller.rb` | `api/v1/categorization_controller_unit_spec.rb` | YES | 13 |
| `api/v1/patterns_controller.rb` | `api/v1/patterns_controller_unit_spec.rb` | YES | 47 |
| `api/v1/categories_controller.rb` | `api/v1/categories_controller_unit_spec.rb`, `api/v1/categories_controller_optimized_spec.rb` | YES | 14+9 = 23 |
| `categories_controller.rb` | -- | **NO** | 0 |
| `concerns/bulk_operation_monitoring.rb` | -- | **NO** | 0 |

### Request Specs (additional integration coverage)

| Spec File | Example Count |
|---|---|
| `requests/api/v1/categorization_spec.rb` | 20 |
| `requests/api/v1/patterns_spec.rb` | 15 |
| `requests/api/v1/patterns_security_spec.rb` | 15 |
| `requests/api/v1/patterns_performance_spec.rb` | 14 |

---

## 4. Bulk Operations Services Cross-Reference

| Service File | Spec File(s) | Has Spec? | Example Count |
|---|---|---|---|
| `bulk_operations/base_service.rb` | -- | **NO** | 0 |
| `bulk_operations/categorization_service.rb` | -- | **NO** | 0 |
| `bulk_operations/deletion_service.rb` | `bulk_operations/deletion_service_spec.rb` | YES | 74 |
| `bulk_operations/status_update_service.rb` | -- | **NO** | 0 |

### Jobs

| Job File | Spec File | Has Spec? | Example Count |
|---|---|---|---|
| `bulk_categorization_job.rb` | `bulk_categorization_job_spec.rb` | YES | 22 |

---

## 5. Coverage Gaps -- Files WITHOUT Specs

| # | Source File | Priority | Notes |
|---|---|---|---|
| 1 | `app/services/categorization/expense_collection_adapter.rb` | HIGH | Adapter translating expense collections -- untested |
| 2 | `app/services/categorization/learning_result.rb` | MEDIUM | Value object for learning results -- likely simple |
| 3 | `app/services/categorization/performance_tracker.rb` | HIGH | Tracks categorization performance metrics -- referenced by many specs but never tested directly |
| 4 | `app/services/categorization/monitoring/engine_integration.rb` | MEDIUM | Integrates monitoring with the categorization engine |
| 5 | `app/services/categorization/monitoring/metrics_collector.rb` | HIGH | Collects categorization metrics -- core monitoring |
| 6 | `app/services/bulk_operations/base_service.rb` | HIGH | Base class for all bulk operations -- shared behavior untested |
| 7 | `app/services/bulk_operations/categorization_service.rb` | HIGH | Core bulk categorization logic -- critical business path |
| 8 | `app/services/bulk_operations/status_update_service.rb` | MEDIUM | Bulk status update operations |
| 9 | `app/controllers/categories_controller.rb` | MEDIUM | Main categories CRUD controller (API controllers are covered) |
| 10 | `app/controllers/concerns/bulk_operation_monitoring.rb` | LOW | Monitoring concern for bulk operations |
| 11 | `app/controllers/expenses_controller.rb` (categorization logic) | LOW | Has spec (`expenses_controller_unit_spec.rb`) but categorization-specific paths may not be fully covered |

---

## 6. Spec Quality Assessment

### Tests with real behavior (GOOD)

- **`engine_spec.rb`** (34 examples): Uses real objects (`create_test_engine`), tests actual categorization flows with real database records. Covers user preferences, pattern matching, and shutdown behavior.
- **`pattern_learner_spec.rb`** (37 examples): Tests real pattern creation and strengthening with database writes. Validates confidence weight calculations, duplicate handling, and correction flows.
- **`confidence_calculator_spec.rb`** (55 examples): Uses real expense/pattern objects with realistic data including amount stats and temporal stats. Tests all confidence factors.
- **`bulk_categorization_service_spec.rb`** (45 examples): Uses stubbed builds for speed where appropriate, includes shared contexts. Tests preview, execution, edge cases.
- **`categorization_pattern_unit_spec.rb`** (108 examples): Comprehensive model testing with validations, associations, scopes, instance methods. Tests edge cases like nil values and boundary conditions.

### Tests with excessive mocking (CAUTION)

- **`orchestrator_spec.rb`** (32 examples): Uses test doubles for all dependencies (`double("PatternCache")`, etc.). While this tests the orchestrator in isolation, it may miss integration issues. However, `orchestrator_integration_spec.rb` (19 examples) compensates by testing with real services.

### Stale / problematic specs

- **`monitoring/dashboard_helper_optimized_spec.rb`** (34 examples): **ALL SKIPPED**. Entire file is skipped with `before { skip }` due to stale references to `PatternCache`, `PerformanceTracker`, and `METRICS_CACHE_TTL` constant.
- **`orchestrator_debug_spec.rb`** (1 example): Debug/diagnostic test with `puts` statements -- should be cleaned up or removed.

### Pending / skipped markers

| File | Marker | Reason |
|---|---|---|
| `orchestrator_improvements_spec.rb:180` | `pending` | "MonitoringService::PerformanceTracker not available" |
| `orchestrator_improvements_spec.rb:199` | `pending` | "MonitoringService::ErrorTracker not available" |
| `pattern_learner_spec.rb:391` | `xit` | "uses provided threshold date (pending investigation)" |
| `monitoring/dashboard_helper_optimized_spec.rb` | `skip` (all 34) | "DashboardHelperOptimized spec is stale -- needs rewrite" |

### Edge case coverage

- **Well covered**: `categorization_pattern_edge_cases_spec.rb` (26 examples) specifically tests edge cases. `lru_cache_spec.rb` (75 examples) tests thread safety, eviction, and boundary conditions.
- **Gaps**: `performance_tracker.rb` has zero tests despite being a dependency of the orchestrator and engine.

---

## 7. Test Execution Results

```
Command: bundle exec rspec spec/services/categorization/ spec/models/categorization_pattern_spec.rb \
  spec/models/categorization_pattern_fixes_spec.rb spec/models/categorization_pattern_edge_cases_spec.rb \
  spec/models/categorization_models_integration_spec.rb spec/models/categorization_pattern_unit_spec.rb \
  spec/models/composite_pattern_spec.rb spec/models/composite_pattern_unit_spec.rb \
  spec/models/category_spec.rb spec/models/category_unit_spec.rb \
  spec/models/canonical_merchant_unit_spec.rb --tag unit --format progress

Result: 1,147 examples, 0 failures, 36 pending
Time:   22.24 seconds
Seed:   18919
```

---

## 8. Recommendations

### Immediate (HIGH priority)

1. **Write specs for `bulk_operations/categorization_service.rb`** -- Critical business path with no tests.
2. **Write specs for `bulk_operations/base_service.rb`** -- Shared base class, failures here cascade to all bulk operations.
3. **Write specs for `performance_tracker.rb`** -- Heavily used as a dependency but never directly tested.
4. **Write specs for `monitoring/metrics_collector.rb`** -- Core metrics collection without coverage.
5. **Write specs for `expense_collection_adapter.rb`** -- Adapter logic should be validated.

### Short-term (MEDIUM priority)

6. **Rewrite `monitoring/dashboard_helper_optimized_spec.rb`** -- 34 examples exist but are all skipped. Either fix references or remove the file.
7. **Write specs for `monitoring/engine_integration.rb`** and `bulk_operations/status_update_service.rb`.
8. **Write specs for `categories_controller.rb`** (main, non-API controller).
9. **Resolve 3 pending/xit markers** in `orchestrator_improvements_spec.rb` and `pattern_learner_spec.rb`.
10. **Write specs for `learning_result.rb`** -- Value object, should be quick to test.

### Cleanup

11. **Remove or convert `orchestrator_debug_spec.rb`** -- Contains `puts` debug output, only 1 example, adds no regression value.
12. **Audit `orchestrator_spec.rb` mocking** -- Consider adding more integration paths to complement the heavy mocking.
