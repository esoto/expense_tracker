# Categorization Completion -- Tickets Created

**Date:** 2026-03-27
**Project:** [Categorization Completion](https://linear.app/personal-brand-esoto/project/categorization-completion-3797767db4ed)
**Based on:** Phase 1 Investigation (categorization domain inventory, test coverage analysis, implementation gap analysis)

---

## Summary

| Metric | Value |
|--------|-------|
| New tickets created | 7 |
| Pre-existing tickets (not duplicated) | 6 (PER-168 through PER-173) |
| Total story points (new) | 13 |
| Total story points (all, including existing) | ~30 |

---

## New Tickets Created

### By Priority

#### High (2 tickets, 6 points)

| ID | Title | Estimate |
|----|-------|----------|
| PER-193 | Add specs for BulkOperations::BaseService | 3 |
| PER-194 | Add specs for BulkOperations::CategorizationService | 3 |

#### Medium (2 tickets, 4 points)

| ID | Title | Estimate |
|----|-------|----------|
| PER-195 | Add specs for BulkOperations::StatusUpdateService | 2 |
| PER-196 | Resolve 3 pending/xit specs in categorization test suite | 2 |

#### Low (3 tickets, 3 points)

| ID | Title | Estimate |
|----|-------|----------|
| PER-197 | Remove orchestrator_debug_spec.rb debug file | 1 |
| PER-198 | Add spec for CategoriesController (non-API) | 1 |
| PER-199 | Add spec for BulkOperationMonitoring concern | 1 |

### By Category

#### Test Coverage (5 tickets, 10 points)

- **PER-193** -- BulkOperations::BaseService specs
- **PER-194** -- BulkOperations::CategorizationService specs
- **PER-195** -- BulkOperations::StatusUpdateService specs
- **PER-198** -- CategoriesController specs
- **PER-199** -- BulkOperationMonitoring concern specs

#### Test Quality (1 ticket, 2 points)

- **PER-196** -- Resolve 3 pending/xit specs (namespace mismatch, missing ErrorTracker)

#### Cleanup (1 ticket, 1 point)

- **PER-197** -- Remove debug spec file

---

## Pre-Existing Tickets (Not Duplicated)

These tickets were already created before this session and cover the most critical gaps:

| ID | Title | Category |
|----|-------|----------|
| PER-168 | Missing PatternImporter/Exporter/Analytics services | Missing services (CRITICAL) |
| PER-169 | Document categorization entry points | Architecture |
| PER-170 | Add specs for 6 uncovered categorization services | Test coverage |
| PER-171 | Fix 34 skipped specs in dashboard_helper_optimized_spec | Test quality |
| PER-172 | Update CLAUDE.md accuracy | Documentation |
| PER-173 | Clean up stale docs | Cleanup |

---

## Gaps Validated and Intentionally Skipped

The following gaps from the investigation were validated but **not ticketed** because they are either future-phase work, not blocking, or low value:

| Gap | Reason Skipped |
|-----|---------------|
| ML/AI phases (Naive Bayes, LLM, Vector DB) | Explicitly planned as future phases, not current gaps |
| XLSX export `NotImplementedError` | Documented intentional limitation; `caxlsx` gem not added yet; no user demand |
| Monitoring production wiring (StatsD/Prometheus/Grafana) | Code exists with `if defined?(StatsD)` guards; works fine without external services; production ops concern, not dev gap |
| CategorizationSerializer existence | Verified: it exists at `app/serializers/api/v1/categorization_serializer.rb` -- not a gap |
| Composite pattern seed data | Model works; seed data is an ops task, not a code gap |
| Multiple Matchers architecture | Single FuzzyMatcher with 4 algorithms covers all needs; CLAUDE.md inaccuracy is tracked in PER-172 |

---

## Recommended Execution Order

1. **PER-168** (Critical) -- Fix broken admin endpoints first; these cause 500 errors in production
2. **PER-193** + **PER-194** (High) -- BulkOperations base + categorization specs; critical business path
3. **PER-171** (High) -- Fix 34 skipped dashboard specs
4. **PER-170** (High) -- Add specs for 6 uncovered categorization services
5. **PER-195** + **PER-196** (Medium) -- StatusUpdate specs + resolve pending markers
6. **PER-169** (Medium) -- Document entry points (Engine vs Orchestrator vs Enhanced)
7. **PER-197** + **PER-198** + **PER-199** (Low) -- Cleanup and minor coverage gaps
8. **PER-172** + **PER-173** (Low) -- Documentation accuracy and stale doc cleanup

Tickets 2-4 can be parallelized across agents. Tickets 7-8 can be batched into a single session.
