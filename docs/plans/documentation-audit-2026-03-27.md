# Documentation & Planning Structure Audit

**Date:** 2026-03-27
**Scope:** Local docs, CLAUDE.md, Obsidian, Linear, Memory files

---

## 1. Documentation Inventory

### Local `docs/` Directory

#### `docs/plans/` (6 files, all dated 2026-03-26)

| File | Lines | Summary | Status |
|------|-------|---------|--------|
| `qa-scenarios-inventory.md` | 14,657+ tokens | Complete E2E test scenario inventory (~320 scenarios across 38 controllers). Thorough and well-structured. | Current |
| `qa-playbook-group-a-core-expenses.md` | 2,023 | QA playbook for core expense CRUD flows | Current |
| `qa-playbook-group-b-dashboard-mobile.md` | 1,911 | QA playbook for dashboard and mobile | Current |
| `qa-playbook-group-cd-bulk-email-sync.md` | 3,166 | QA playbook for bulk ops, email, sync | Current |
| `qa-playbook-group-efg-admin-api-budget.md` | 3,518 | QA playbook for admin, API, budgets | Current |
| `2026-03-26-mobile-card-layout-design.md` | 810 lines | Detailed implementation plan for PER-133 mobile card layout. Includes TDD steps, code, agent dispatch notes. | Current but partially superseded -- PER-133 is now Done |

#### `docs/qa-runs/2026-03-27/` (8 markdown files + 8 screenshots)

QA execution results from a manual test run. Contains pass/fail results and screenshots of actual UI states. Current and useful as a test baseline.

#### `docs/categorization_improvement/` (36 files, 22,467 total lines)

| File/Dir | Summary | Status |
|----------|---------|--------|
| `README.md` | Overview of 3-tier categorization system (pattern/ML/AI) | **STALE** -- last updated "2024", references unreleased features |
| `DEVELOPMENT_PLAN_SUMMARY.md` | Hour estimates, team allocation, budget for 3 options | **STALE** -- written for a team of 2-4+ devs, irrelevant to solo dev workflow |
| `PHASE_1_STATUS_UPDATE.md` | Status from 2025-08-11, shows 8/11 tasks complete | **STALE** -- 7+ months old, doesn't reflect current state |
| `PHASE_1_GAP_ANALYSIS.md` | Gap analysis from 2025-08-17/20 | **STALE** -- predates QA remediation work |
| `option1_tasks/` (22 files) | Granular task breakdowns for pattern-based categorization | **STALE** -- these tasks were completed in 2025 |
| `option2_tasks/` (1 file) | ML foundation tasks | **STALE** -- never implemented |
| `option3_tasks/` (1 file) | AI foundation tasks | **STALE** -- never implemented |
| `implementation_plan.md` | Rollout timeline | **STALE** |
| `technical_architecture.md` | System design | **PARTIALLY STALE** -- core architecture was implemented but has evolved |
| `testing_strategy.md` | Test approach for categorization | **STALE** |

**Verdict:** The entire `docs/categorization_improvement/` directory is historical. Phase 1 was implemented in 2025. Phases 2 and 3 (ML, AI) were never started. This is 22,000+ lines of stale documentation.

#### Referenced but Missing

| Referenced In | File | Status |
|---------------|------|--------|
| CLAUDE.md | `docs/plans/2026-02-14-qa-remediation-plan.md` | **MISSING** -- file does not exist |
| `PHASE_1_STATUS_UPDATE.md` | `docs/performance/scalability_projections.md` | **MISSING** -- directory does not exist |

---

## 2. CLAUDE.md Accuracy

### Architecture Section -- Detailed Comparison

| Claim | Actual | Accurate? |
|-------|--------|-----------|
| "28 ActiveRecord models" | 26 model files in `app/models/` (including `application_record.rb` and `soft_delete.rb` concern) | **WRONG** -- should be ~24 domain models or 26 files |
| "38 controllers" | 37 controller files (some duplicated paths suggest concerns counted) | **CLOSE** -- minor discrepancy |
| "49 Stimulus controllers" | 48 controller JS files | **CLOSE** -- was 49, one was renamed/merged |
| "80+ domain-organized service objects across 12+ domains" | 83 service files across ~10 domain directories | **CLOSE** -- domain count slightly inflated |
| "15 background jobs" | 15 job files | **CORRECT** |
| "44 migrations" | 45 migration files | **CLOSE** -- one migration added |
| "350+ test files" | 293 spec files | **WRONG** -- should be ~293 |
| "7,400+ unit tests" | ~8,744 test examples (grep count); Memory says "7,500+" | **OUTDATED** -- has grown significantly |
| Rails version "8.1.2" | Gemfile: `gem "rails", "~> 8.1.2"` | **CORRECT** |

### Service Architecture Section

The listed service domains are mostly accurate but have some issues:

- **Email Domain**: Accurately describes `ProcessingService`, `SyncService`, `EncodingService`. Also has `email_processing/` subdomain with `Fetcher`, `Parser`, `Processor`, `Strategies` -- not mentioned.
- **Categorization Domain**: Says "18+ services" -- actual count is ~25 files in `categorization/` plus `categorization_service.rb`. Understated.
- **Broadcast Domain**: Lists 5 services -- actual is 7 (`broadcast_analytics.rb`, `broadcast_error_handler.rb`, `broadcast_feature_flags.rb`, `broadcast_rate_limiter.rb`, `broadcast_reliability_service.rb`, `broadcast_request_validator.rb`, `broadcast_retry_orchestrator.rb`). Missing `BroadcastFeatureFlags` and `BroadcastRequestValidator`.
- **Bulk Operations Domain**: Accurate.
- **Missing entirely**: `bulk_categorization/` domain (3 services: `apply_service.rb`, `grouping_service.rb`, `undo_service.rb`), `patterns/` domain (3 services), `infrastructure/` domain (3 services), various root-level services (`sync_progress_updater.rb`, `sync_session_creator.rb`, etc.)

### QA Remediation Status -- SIGNIFICANTLY OUTDATED

CLAUDE.md says:
- Phase 0 (Emergency Fixes): Complete -- 7/7
- Phase 1 (Critical Performance): Complete -- 7/8
- Phase 2 (Security Hardening): Complete -- 8/8
- Phase 3 (UX & Design): In progress -- 10 tasks
- Phase 4 (Performance Polish): Pending -- 6 tasks
- Phase 5 (Cleanup & Polish): Pending -- 5 tasks

**Actual status from Linear (2026-03-27):**

The QA Remediation project in Linear uses different milestone names than CLAUDE.md's Phase 0-5 structure. The original plan file (`2026-02-14-qa-remediation-plan.md`) no longer exists.

Current Linear milestones and their status:

| Milestone | Progress | Status |
|-----------|----------|--------|
| Bug Fixes | 100% | **DONE** -- PER-118 (Stimulus errors), PER-120 (flaky tests) |
| PR Follow-ups | 100% | **DONE** -- PER-115 (undo UX), PER-116 (keyboard tests), PER-117 (flash dismiss), PER-119 (i18n migration) |
| Performance Polish | 87.5% | **NEARLY DONE** -- PER-124 (dashboard queries), PER-125 (cache versions), PER-126 (index pruning), PER-127 (thread pool singleton), PER-128 (filter caching), PER-129 (conditional invalidation) all Done. PER-155 (CacheVersioning concern extraction) is Backlog. |
| Cleanup & Polish | 100% | **DONE** -- PER-130 (blue mockups), PER-131 (English strings), PER-132 (dynamic bank filter), PER-133 (mobile layout), PER-134 (email cascade). Plus follow-ups: PER-165 (i18n card strings), PER-166 (rename controller) both Done. |

**Remaining open tickets under QA Remediation:**
- PER-155: Extract shared CacheVersioning concern (Backlog)
- PER-164: Mobile category picker wiring (In Progress)
- PER-167: Optimize double rendering mobile/desktop (Backlog)
- PER-156 through PER-163: Sub-tasks of PER-133, all Backlog but parent is Done

**Bottom line:** CLAUDE.md's Phase 0-5 structure no longer matches Linear's milestone structure. Phases 4 and 5 are essentially complete, not "Pending" as stated.

### Completed Epics

CLAUDE.md lists Epics 1-3 as complete. This appears accurate based on the UX Dashboard Improvements project summary ("Epics 1-3 complete. Epic 4 (simplification) pending.").

### Development Rules

CLAUDE.md references 13 rules files. All exist in `rules/`. However:
- `rules/style-guide.md` exists but is NOT listed in CLAUDE.md's Development Rules section.

---

## 3. Obsidian Documentation

Found 30 Obsidian notes under `Esteban's brain/Personal Brand/Expense tracker/`:

| Category | Notes | Description |
|----------|-------|-------------|
| Root level | 4 | QA Phase 4 Performance, Users account, Linear Structure Convention, Multi-Agent Development Workflow, UX Epic 4 Dashboard Simplification |
| Design/ | 3 | Accessibility, Design System, Design Specification |
| Backlog/ | 4 | Rate Limiting Config, Production Deployment Checklist, Testing Backlog, Queue Accessibility Violations |
| Projects/Categorization/ | 9 | Overview, Epic 1, Phase 1 tasks (1.7.2-1.7.4), Gap Analysis, Engine Architecture, Phase 2 & 3, Technical Architecture, Testing Strategy, Dashboard Strategy Migration, Rails Concurrency Guide |
| Projects/Multi-Tenancy/ | 2 | Multi-Tenancy overview, Requirements RBAC |
| Projects/UX Dashboard/ | 1 | UX Dashboard Improvements |
| Projects/Enterprise Platform/ | 1 | Enterprise Platform |

**Consistency issues:**
- The `docs/categorization_improvement/` local docs duplicate content that also lives in Obsidian under `Projects/Categorization/`. Obsidian is the intended canonical source per Memory ("Documentation lives in Obsidian + Linear").
- The local `docs/` folder should ideally only contain execution artifacts (QA playbooks, run results) and implementation plans, not long-lived documentation.

---

## 4. Linear Project Status

### Projects in "Personal Brand" team

| Project | Status | Expense Tracker? |
|---------|--------|-------------------|
| QA Remediation | Backlog (but milestones mostly Done) | Yes |
| UX Dashboard Improvements | Backlog | Yes |
| Multi-Tenant | Backlog | Yes |
| Expense Tracker | Backlog | Yes (general) |
| Salary Calculator - Application Review | Backlog | No |
| Portfolio | In Progress | No |
| Personal Tech Blog | Planned | No |

### QA Remediation Tickets -- Stale/Mismatched

**Tickets Done but with open sub-tasks:**
- PER-133 (mobile layout) is marked Done, but sub-tasks PER-156 through PER-163 are all still in Backlog. These sub-tasks were created as an implementation plan before the work was done in a single session. They should be closed or archived.

**Tickets that could be stale:**
- PER-155 (CacheVersioning concern extraction) -- Backlog, no assignee, medium priority. This is a follow-up from PR review feedback. Still valid but not actively worked.
- PER-167 (optimize double rendering) -- Backlog, low priority. Valid future optimization.

**Tickets In Progress:**
- PER-164 (mobile category picker) -- actively being worked, has a commit on the branch.

---

## 5. Memory File Review

### `MEMORY.md`

| Entry | Accurate? | Notes |
|-------|-----------|-------|
| Multi-Agent Workflow | Yes | Still relevant |
| Worktree DB Isolation | Yes | Still relevant |
| Commit Conventions | Yes | Still relevant |
| "7,500+ unit tests" | **OUTDATED** | Now ~8,700+ examples |
| "Documentation lives in Obsidian + Linear (docs/ folder cleaned out)" | **WRONG** | `docs/` folder has 50+ files totaling 22,000+ lines. Not cleaned out. |
| PR #180 merged | Yes | Confirmed in git log |
| PER-133 "in progress -- design phase" | **OUTDATED** | PER-133 is Done, merged as PR #186 |
| Agent Test Execution Issues | Yes | Still relevant guidance |
| Worktree DB Cleanup | Yes | Still relevant |
| "12 QA tickets closed" | **OUTDATED** | Now 18+ tickets closed |

### `workflow_multi_agent.md`

Accurate and still relevant. Good guidance on agent pipeline, Sonnet agent prompts, review process.

### `workflow_agent_issues.md`

Accurate record of 2026-03-26 issues. Still relevant as guidance. Point 5 suggests agents use `--no-verify` which conflicts with project rules. Should add a note clarifying the resolution.

### `workflow_auto_test_db.md`

Still relevant. Documents a desired feature (auto DB isolation per worktree) that hasn't been implemented yet.

---

## 6. Recommendations

### Priority 1: Fix CLAUDE.md Accuracy (High Impact)

1. **Update QA Remediation status.** Remove the Phase 0-5 structure (source plan is deleted). Replace with current Linear milestone status: Bug Fixes (Done), PR Follow-ups (Done), Performance Polish (87.5%), Cleanup & Polish (Done). Remove reference to deleted plan file.

2. **Update counts.** Models: 26 files. Stimulus controllers: 48. Test files: ~293. Unit tests: ~8,700+. Migrations: 45.

3. **Add `style-guide.md` to rules list** or remove the file if unused.

4. **Update service architecture** to reflect `bulk_categorization/`, `patterns/`, `infrastructure/` domains and the full broadcast service list.

### Priority 2: Clean Up Stale Documentation (Medium Impact)

5. **Delete or archive `docs/categorization_improvement/`.** This is 36 files / 22,000+ lines of stale documentation from 2025. Phase 1 was completed. Phases 2-3 were never started. The canonical docs live in Obsidian. Options:
   - Delete entirely (Obsidian has the content)
   - Move to `docs/archive/categorization_improvement/` with a note

6. **Close orphaned Linear sub-tasks.** PER-156 through PER-163 (sub-tasks of Done ticket PER-133) should be closed as their parent is complete. The work was done in a single implementation session, not task-by-task.

### Priority 3: Update Memory Files (Medium Impact)

7. **Update MEMORY.md:**
   - Change "7,500+" to "8,700+"
   - Fix "docs/ folder cleaned out" -- it has 50+ files
   - Update PER-133 status to Done
   - Update QA ticket count (18+ closed, not 12)
   - Add note about PER-164 being the current active ticket

8. **Update `workflow_agent_issues.md`:** Add note that `--no-verify` conflicts with project rules and should not be used.

### Priority 4: Improve Documentation Structure (Low Impact)

9. **Establish clear ownership.** The split between `docs/`, Obsidian, and Linear creates confusion. Consider:
   - `docs/plans/` = implementation plans (short-lived, tied to tickets)
   - `docs/qa-runs/` = QA execution results
   - Obsidian = long-lived architecture docs, design specs, backlogs
   - Linear = ticket tracking and status

10. **Add a `docs/README.md`** explaining what belongs in each location.

11. **Review QA playbooks for staleness.** The playbook files were created 2026-03-26. They are current but will become stale as the app evolves. Consider whether they should be maintained or treated as point-in-time artifacts.

---

## Summary of Findings

| Area | Severity | Issues Found |
|------|----------|--------------|
| CLAUDE.md counts | Medium | 5 inaccurate numbers (models, controllers, tests, specs, migrations) |
| CLAUDE.md QA status | High | Phase structure no longer matches Linear; phases 4-5 shown as "Pending" are actually Done |
| CLAUDE.md references | Medium | Links to deleted plan file; missing rules file from list |
| Stale docs | Medium | 36 files / 22K lines in `docs/categorization_improvement/` from 2025 |
| Memory accuracy | Medium | 4 outdated entries in MEMORY.md |
| Linear hygiene | Low | 8 orphaned sub-tasks on completed parent ticket |
| Missing docs | Low | No referenced QA remediation plan; no performance docs directory |
