# QA Remediation — Completed Tickets Archive

**Archived:** 2026-03-30
**Project:** QA Remediation (Linear)
**Reason:** Tickets archived to free Linear workspace capacity for Categorization Completion phase tickets.

---

## Completed Tickets (50)

| ID | Title | PR |
|----|-------|-----|
| PER-155 | Extract shared CacheVersioning concern + fix lazy mutex init | #250 |
| PER-167 | Optimize double rendering of expenses on mobile/desktop | #227 |
| PER-168 | Create missing PatternImporter, PatternExporter, PatternAnalytics services | #198 |
| PER-169 | Document canonical categorization entry point (4 overlapping services) | #228 |
| PER-170 | Add specs for 6 categorization services missing test coverage | — |
| PER-171 | Fix 34 skipped specs in dashboard_helper_optimized_spec.rb | #225 |
| PER-172 | Update CLAUDE.md with accurate QA phase status and metrics | #221 |
| PER-173 | Clean up stale categorization docs and orphaned Linear tickets | #226 |
| PER-175 | Handle missing/empty expense params in webhook endpoint | #193 |
| PER-176 | Handle ETag conditional GET without crashing | #201 |
| PER-177 | Handle empty expense_ids in bulk destroy | #202 |
| PER-178 | Missing i18n keys for budget periods (es.budgets.periods) | #220 |
| PER-179 | Correct admin login failure to render form instead of redirecting | #194 |
| PER-180 | Ensure redirect-back to requested URL after admin login | #203 |
| PER-181 | Clear password field after failed login attempt | #200 |
| PER-182 | Add missing notes column to expenses table | #190 |
| PER-183 | Convert page param to integer in ExpenseFilterService | #192 |
| PER-184 | Resolve Chart.js date-fns adapter import error on dashboard | #204 |
| PER-185 | Mobile: horizontal overflow at 375px viewport (content 571px wide) | — |
| PER-186 | Allow authenticated users to access /categories.json for bulk ops | #196 |
| PER-187 | Bulk selection: action buttons enabled with 0 items selected | — |
| PER-188 | Bulk modal close/cancel buttons non-functional | — |
| PER-189 | Bulk selection: multiple a11y and state management bugs | #229 |
| PER-190 | Email accounts: Turbo Drive controller pollution from admin/patterns | #197 |
| PER-191 | i18n: untranslated strings across email accounts and sync pages | #223 |
| PER-192 | SVG accessibility: 114 of 115 SVGs missing aria-hidden attribute | #230 |
| PER-200 | Admin patterns page accessible without authentication | #191 |
| PER-201 | Guard dropdown_controller targets to prevent TypeError | #199 |
| PER-203 | Remove duplicate x100 multiplication on pattern success rate display | #205 |
| PER-204 | Composite patterns new/edit view templates missing | #231 |
| PER-205 | Rate limiting not enforced on analytics export and pattern testing endpoints | #222 |
| PER-207 | Sync conflicts "Seleccionar todo" doesn't check row checkboxes | — |
| PER-208 | bulk_destroy returns undo_id: null — no UI undo for bulk deletes | #206 |
| PER-209 | Expense delete redirects to /sync_conflicts instead of /expenses | #207 |
| PER-210 | Filter persistence controller not saving/restoring state | #233 |
| PER-211 | "Ver resumen" collapsible toggle not expanding on mobile | — |
| PER-212 | Bulk categorization CSV export returns admin login HTML instead of CSV | #209 |
| PER-213 | Session expiry during Turbo Drive form submissions | #232 |
| PER-214 | Fix DashboardService date boundary bug — last_month_total returns 0 | #213 |
| PER-215 | Fix MetricsRefreshJob test — cache key format mismatch after PR #182 | #215 |
| PER-216 | Fix test pollution in categorization_spec and pattern_learner_integration_spec | #214 |
| PER-217 | Investigate flaky test: categorization_spec.rb:89 fails intermittently | #249 |
| PER-218 | expense_params permits :notes but Expense model has no notes column | — |
| PER-219 | Failed login redirects to /login instead of /admin/login | #236 |
| PER-220 | Post-login redirect goes to /admin/patterns instead of requested page | — |
| PER-221 | Expense delete redirects to /sync_conflicts instead of /expenses | #238 |
| PER-222 | Chart.js/Chartkick broken — 'No charting libraries found' on dashboard | #241 |
| PER-223 | dropdown_controller crashes on /admin/patterns — blocks all admin UI | #235 |
| PER-224 | pattern_form_controller updateValueHelp throws null error on type change | #240 |
| PER-225 | 'Nuevo Presupuesto' link navigates to /sync_sessions/3 instead of /budgets/new | #237 |
| PER-226 | Analytics statistics/performance HTML views return 406 Not Acceptable | #247 |
| PER-227 | Composite pattern create returns 422 validation error | #242 |
| PER-228 | Conflict resolution modal never displays content | #243 |
| PER-229 | /bulk_categorizations/export.csv routes to #show instead of export action | #244 |
| PER-230 | Analytics refresh endpoint returns 422 with valid CSRF token | #246 |
| PER-231 | 'Seleccionar todo' checkbox doesn't check individual row checkboxes | #248 |
| PER-232 | /api/health returns 503 when pattern_cache is empty on app start | #245 |
| PER-233 | /api/v1/patterns/statistics returns 404 — route conflict with show action | #239 |
| PER-234 | Dashboard 7px horizontal overflow at 375px viewport | #253 |
| PER-235 | 72 decorative SVGs still missing aria-hidden="true" after PER-192 | #254 |
| PER-236 | filter_persistence_controller auto-redirects to /expenses on page load | #252 |
| PER-237 | toggle_active.turbo_stream.erb template missing — 500 on Turbo Stream toggle | #255 |
| PER-238 | queue_monitor_controller asset fails to compile — MIME type mismatch | — |
| PER-239 | accessibility_enhanced_controller throws TypeError on liveRegionTarget getter | #251 |
