<!-- project-context-section -->
## Project Context

<!-- TODO: Fill in the details below. Check Gemfile, package.json, or Makefile for commands. -->

**What this app does:** Expense tracking with ML-powered categorization, email sync, admin panel, and iPhone Shortcuts API

**Stack:** Rails 8.1.2, PostgreSQL (pg_trgm, unaccent), Hotwire (Turbo + Stimulus), Tailwind CSS, Solid Queue/Cache/Cable (no Redis), Propshaft, Import Maps

**Common commands:**

- `bin/rails server` — Start dev server
- `bin/rails console` — Rails console
- `bundle exec rspec` — Run RSpec tests
- `bin/rails db:migrate` — Run migrations
- `bin/rails db:setup` — Create DB, load schema, seed
- `bin/rails db:reset` — Drop and recreate DB
- `tailwindcss:build` / `tailwindcss:watch` — Build/watch Tailwind CSS
- `bundle exec rubocop`

**Test command:** `bundle exec rspec --tag unit`

**Lint command:** `bundle exec rubocop`

**Security scan:** `bundle exec brakeman`

**Notes:**
- NEVER push directly to main. ALL code changes go through a PR — no exceptions, not even 1-line hotfixes. Create a branch, commit, push, open PR, review, then merge.
- NEVER use `--no-verify` to bypass pre-commit hook. Hook failure = commit did NOT happen — fix, re-stage, new commit (do NOT amend).
- Design system: Financial Confidence palette — `teal-*` (primary), `amber-*` (warning), `rose-*` (error), `emerald-*` (success), `slate-*` (neutrals). NEVER use `blue-*`, `gray-*`, `red-*`, `yellow-*`, or `green-*`. Full palette: `.claude/context/frontend/design-system.md`

## Git Pre-commit Hook

A pre-commit hook is available to automatically run code quality checks and security scanning before allowing commits. This ensures code quality and security standards are maintained.

**Setup:** Run `./bin/setup-git-hooks` after cloning the repository to install the hooks.

The hook runs:
1. **RuboCop** - Ensures code style compliance
2. **Brakeman** - Security vulnerability scanner
3. **RSpec unit tests** - Runs only tests tagged with `:unit` (uses `bundle exec rspec --tag unit`)

## Git Worktrees & Test Database Isolation

When multiple sessions run tests concurrently, **deadlock errors** (`PG::TRDeadlockDetected`) occur.

**Solution:** Use git worktrees with a separate test database per worktree.

1. `git worktree add .worktrees/<branch-name> -b <branch-name> main`
2. Change test DB name in `config/database.yml`: `expense_tracker_test_worktree<%= ENV['TEST_ENV_NUMBER'] %>`
3. `RAILS_ENV=test bin/rails db:create && RAILS_ENV=test bin/rails db:schema:load`

> `.worktrees/` is gitignored. Do NOT commit the `database.yml` change.

## Architecture & Conventions

Detailed conventions, patterns, and architectural decisions: `.claude/context/` (5 domains: backend, frontend, database, security, project).

<!-- project-context-section -->

