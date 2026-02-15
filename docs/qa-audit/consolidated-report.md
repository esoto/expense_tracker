# Consolidated QA Audit Report - Expense Tracker

**Date**: 2026-02-14
**Methodology**: 4 parallel specialized agents (Security, Performance, Design/UX, User Experience)
**Total Findings**: 110 across all perspectives

---

## Executive Summary

| Perspective | CRITICAL | HIGH | MEDIUM | LOW | INFO | Total |
|-------------|----------|------|--------|-----|------|-------|
| Security | 4 | 10 | 10 | 4 | 0 | **28** |
| Performance | 5 | 10 | 12 | 5 | 0 | **32** |
| Design/UX | 3 | 14 | 8 | 5 | 0 | **30** |
| User Experience | 2 | 5 | 7 | 4 | 2 | **20** |
| **TOTAL** | **14** | **39** | **37** | **18** | **2** | **110** |

### Application Health Score: 45/100 (Needs Significant Work Before Production)

The app has excellent test coverage (5900 specs), solid architecture, and good core UX patterns. However, **critical authentication gaps**, **performance bottlenecks**, and **incomplete localization** make it unfit for production deployment without remediation.

---

## TOP 10 MUST-FIX Issues (Cross-Perspective)

### 1. AUTHENTICATION: Multiple Controllers Completely Unprotected
**Found by**: Security (S-01), UX Tester (UX-001) | **Severity**: CRITICAL

`EmailAccountsController`, `BudgetsController`, `SyncConflictsController`, `SyncPerformanceController`, `CategoriesController`, `UndoHistoriesController` have NO authentication. Anyone can CRUD email credentials, budgets, and undo operations.

**Fix**: Add `include Authentication` to `ApplicationController` and explicitly skip only for public endpoints.

---

### 2. AUTHORIZATION: SyncAuthorization Always Returns True
**Found by**: Security (S-02) | **Severity**: CRITICAL

Both `sync_access_allowed?` and `sync_session_owner?` are TODO stubs that return `true`. Any user can access any sync session.

**Fix**: Implement real ownership checks.

---

### 3. PERFORMANCE: Dashboard Fires 50+ Queries Per Load
**Found by**: Performance (P-1, P-2, P-5, P-6) | **Severity**: CRITICAL

`MetricsCalculator.calculate_trends` recalculates all metrics (doubling queries), `calculate_percentage_of_total` fires N+1 per category, and the dashboard action chains 3 heavy service calls sequentially.

**Fix**: Pass calculated metrics to trends, pre-compute totals, consolidate aggregates with `pick()`.

---

### 4. DATA DESTRUCTION: PatternCache.invalidate_all Calls Redis flushdb
**Found by**: Performance (P-3) | **Severity**: CRITICAL

`invalidate_all` calls `redis_client.flushdb` which destroys the ENTIRE Redis database - not just pattern cache keys. This wipes all cached metrics, sessions, and Solid Cache data.

**Fix**: Use namespaced `SCAN` + `DEL` instead of `flushdb`.

---

### 5. SECURITY: Admin Login CSRF Disabled + API CategoriesController Unauthed
**Found by**: Security (S-03, S-04) | **Severity**: CRITICAL

Admin login skips CSRF verification (login CSRF attack vector). API v1 CategoriesController inherits from `ApplicationController` instead of `Api::V1::BaseController`, bypassing all API auth.

**Fix**: Remove CSRF skip. Fix controller inheritance.

---

### 6. UX: Expense Form Broken for Manual Entry
**Found by**: UX Tester (UX-002) | **Severity**: CRITICAL

The form offers "Entrada manual" (blank email_account_id) but `belongs_to :email_account` is required. Manual expense creation always fails validation.

**Fix**: Auto-assign a "manual" email account or remove the blank option.

---

### 7. DESIGN: Navigation Not Responsive + Multiple Pages in English
**Found by**: Design (CRITICAL-2,3,4), UX (UX-015) | **Severity**: CRITICAL

Navigation has no mobile hamburger menu (8 links overflow). Admin patterns, analytics dashboard, bulk categorization, and queue visualization are entirely in English despite Spanish being the app language.

**Fix**: Add responsive navigation. Translate all user-facing views.

---

### 8. PERFORMANCE: N+1 Queries in Bulk Operations and Expense Rows
**Found by**: Performance (P-4), UX (UX-003) | **Severity**: HIGH

`store_bulk_operation` does `Expense.find(id)` per result. `_expense_row.html.erb` executes `Category.all.order(:name)` per row (50 queries per page load).

**Fix**: Use `Expense.where(id: ids).sum(:amount)`. Pass categories as a local to the partial.

---

### 9. SECURITY: WebSocket Auth Bypass + Global Queue Channel
**Found by**: Security (S-10, S-11) | **Severity**: HIGH

WebSocket connection generates random session IDs as fallback (accepting unauthenticated connections). QueueChannel broadcasts to all subscribers without user scoping.

**Fix**: Remove SecureRandom fallback. Add user-scoped queue channels.

---

### 10. UX: No Pagination, Misleading Delete Messages, No Undo Integration
**Found by**: UX (UX-004, UX-005, UX-006) | **Severity**: HIGH

Expenses index has no pagination beyond first 50. Delete confirmation says "cannot be undone" but soft-delete IS undoable. Single-expense delete doesn't offer undo despite the system supporting it.

**Fix**: Add pagination controls. Fix confirmation text. Return undo_id from destroy action.

---

## Findings by Epic

### Epic 1: Sync Status Interface
| # | Source | Severity | Finding |
|---|--------|----------|---------|
| S-02 | Security | CRITICAL | SyncAuthorization always returns true |
| S-10 | Security | HIGH | WebSocket accepts fallback session IDs |
| S-11 | Security | HIGH | QueueChannel broadcasts without user scoping |
| S-09 | Security | HIGH | Client errors endpoint unauthenticated (DoS) |
| S-06 | Security | HIGH | Queue admin key not timing-safe |
| P-13 | Performance | HIGH | Debug `puts` in broadcast_reliability_service |
| D-8 | Design | HIGH | Queue visualization entirely in English |
| D-2 | Design | MEDIUM | Queue monitor JS has English strings |

### Epic 2: Enhanced Metric Cards
| # | Source | Severity | Finding |
|---|--------|----------|---------|
| P-1 | Performance | CRITICAL | calculate_trends recalculates all metrics |
| P-2 | Performance | CRITICAL | N+1 SUM per category in percentage_of_total |
| P-5 | Performance | CRITICAL | Dashboard fires 50+ queries |
| P-6 | Performance | HIGH | 10 separate aggregates instead of 1 pick() |
| P-7 | Performance | HIGH | Median calculated in Ruby memory |
| P-10 | Performance | HIGH | delete_matched is O(n) on Redis keyspace |
| P-14 | Performance | HIGH | ThreadPoolExecutor created per engine instance |
| S-08 | Security | HIGH | MonitoringController token lookup broken |
| UX-009 | UX | MEDIUM | Dashboard metrics hardcoded to CRC |

### Epic 3: Optimized Expense List
| # | Source | Severity | Finding |
|---|--------|----------|---------|
| P-4 | Performance | CRITICAL | N+1 in store_bulk_operation |
| P-15 | Performance | HIGH | Per-expense broadcasting after bulk update |
| UX-003 | UX | HIGH | Category.all loaded per expense row |
| UX-004 | UX | HIGH | Delete confirmation contradicts soft delete |
| UX-005 | UX | HIGH | Dashboard delete lacks undo notification |
| UX-006 | UX | HIGH | No pagination on expenses index |
| S-13 | Security | HIGH | html_safe with user-influenced data |
| UX-013 | UX | MEDIUM | Keyboard shortcut conflict between controllers |
| P-21 | Performance | MEDIUM | VirtualScrollController innerHTML pattern |

### Categorization System
| # | Source | Severity | Finding |
|---|--------|----------|---------|
| S-04 | Security | CRITICAL | API v1 CategoriesController no auth |
| P-3 | Performance | CRITICAL | flushdb destroys entire Redis |
| S-14 | Security | HIGH | PatternManagement permission always true |
| D-2,3 | Design | CRITICAL | Admin patterns + analytics entirely in English |
| D-6 | Design | HIGH | Bulk categorization pages in English |
| P-24 | Performance | MEDIUM | O(m*n) Levenshtein distance memory |

### Cross-Epic / Infrastructure
| # | Source | Severity | Finding |
|---|--------|----------|---------|
| S-01 | Security | CRITICAL | Multiple controllers missing authentication |
| S-03 | Security | CRITICAL | Admin login CSRF disabled |
| UX-002 | UX | CRITICAL | Expense form broken for manual entry |
| D-4 | Design | CRITICAL | Navigation not responsive |
| S-07 | Security | HIGH | Sidekiq Web default credentials |
| S-15 | Security | MEDIUM | CSP commented out globally |
| P-12 | Performance | HIGH | 65+ indexes with significant overlap |
| UX-008 | UX | MEDIUM | Email account deletion cascades destructively |
| UX-010 | UX | MEDIUM | Flash messages never auto-dismiss |

---

## Prioritized Remediation Roadmap

### Phase 0: Emergency Fixes (1-2 days) - BEFORE ANY DEPLOYMENT
1. Add `include Authentication` to `ApplicationController` (fixes S-01, S-12, S-17-S-21, UX-001)
2. Implement SyncAuthorization ownership checks (fixes S-02)
3. Remove admin login CSRF skip (fixes S-03)
4. Fix API v1 CategoriesController inheritance (fixes S-04)
5. Replace `flushdb` with namespaced deletion (fixes P-3)
6. Fix manual expense creation form (fixes UX-002)
7. Remove WebSocket session ID fallback (fixes S-10)

### Phase 1: Critical Performance (3-5 days)
8. Pass metrics to calculate_trends (fixes P-1)
9. Pre-compute total for percentage_of_total (fixes P-2)
10. Consolidate MetricsCalculator aggregates with pick() (fixes P-6)
11. Fix N+1 in store_bulk_operation (fixes P-4)
12. Pass categories as local to _expense_row partial (fixes UX-003)
13. Use PostgreSQL PERCENTILE_CONT for median (fixes P-7)
14. Batch broadcast for bulk operations (fixes P-15)
15. Remove debug puts statements (fixes P-13)

### Phase 2: Security Hardening (3-5 days)
16. Use secure_compare for admin key (fixes S-06)
17. Require Sidekiq credentials in production (fixes S-07)
18. Fix MonitoringController auth method (fixes S-08)
19. Authenticate client errors endpoint (fixes S-09)
20. Add user scoping to QueueChannel (fixes S-11)
21. Fix html_safe usage in helpers (fixes S-13)
22. Remove PatternManagement permission override (fixes S-14)
23. Enable Content Security Policy (fixes S-15)

### Phase 3: UX & Design (1-2 weeks)
24. Add responsive navigation hamburger menu (fixes D-4, UX-015)
25. Translate admin patterns pages to Spanish (fixes D-2)
26. Translate analytics dashboard to Spanish (fixes D-3)
27. Translate bulk categorization to Spanish (fixes D-6)
28. Translate queue visualization to Spanish (fixes D-8)
29. Fix delete confirmation text for soft delete (fixes UX-004)
30. Add pagination to expenses index (fixes UX-006)
31. Integrate undo with single-expense delete (fixes UX-005)
32. Auto-dismiss flash messages (fixes UX-010)
33. Standardize keyboard shortcuts (fixes UX-013)

### Phase 4: Performance Polish (1 week)
34. Refactor dashboard action query consolidation (fixes P-5)
35. Implement cache version key approach (fixes P-10, P-11)
36. Audit and prune duplicate indexes (fixes P-12)
37. Make ThreadPoolExecutor a singleton (fixes P-14)
38. Enable ExpenseFilterService caching (fixes P-17)
39. Conditional cache invalidation on expense commit (fixes P-18)

### Phase 5: Cleanup & Polish (ongoing)
40. Delete or fix mockup files with forbidden blue classes (fixes D-1)
41. Fix remaining English strings (fixes D-7,9,11,12,13)
42. Dynamic bank filter dropdown (fixes UX-014)
43. Mobile table/card layout for expenses (fixes D-4)
44. Fix email account cascade to nullify (fixes UX-008)

---

## Detailed Reports

- [Security Findings](./security-findings.md) - 28 findings
- [Performance Findings](./performance-findings.md) - 32 findings
- [Design/UX Findings](./design-findings.md) - 30 findings
- [User Experience Findings](./user-experience-findings.md) - 20 findings

---

*Generated by multi-agent QA audit on 2026-02-14*
