# Deploy Runbook — User-Model Unification Cutover

One-time runbook for the 14-PR User-model unification deploy (PRs #460–#475, merged to `main` on 2026-04-21 at commit `d727375`). After this deploy ships and smokes green, this file can stay as a reference for future operators.

Three risk surfaces you're dealing with:

1. **First-boot data migration.** `db/migrate/20260420130000_create_default_user_from_admin_users.rb` reads `admin_users` rows and creates `User` rows. PR 14's `drop_admin_users_table` (`db/migrate/20260421160000_drop_admin_users_table.rb`) runs later in the same batch — the drop is safe because rows are already copied, but the first deploy MUST have at least one `admin_users` row when migrations start.
2. **Session-cookie cutover.** Every existing admin cookie becomes invalid at cutover. Log in again at `/login` — there is no more `/admin/login`.
3. **Env-var dependency.** `db/seeds.rb` now creates a `User` (not `AdminUser`) and `abort`s in production if `ADMIN_EMAIL` or `ADMIN_PASSWORD` match the dev sentinels. `config/deploy.yml` already declares both as `env.secret`, so `.kamal/secrets` on the workstation must have real values.

Four sections below. Do them in order.

---

## 1. Pre-flight (T-minus)

Run from the local workstation. Each step is copy-pasteable.

### 1.1 Verify branch state

```bash
cd /Users/esoto/development/expense_tracker
git fetch origin main
git log --oneline origin/main -1   # expect: d727375 feat(cleanup): PR 14/14 ...
```

### 1.2 Verify CI on main

```bash
# Check REQUIRED workflows (CI, Unit Tests) on the current origin/main commit.
# Non-required workflows (e.g. the chronically-red `Test Suite` :performance
# specs) are intentionally NOT blocking — see REQUIRED_WORKFLOWS in
# bin/pre-deploy-check for the authoritative list.
SHA=$(git rev-parse origin/main)
gh run list --branch main --commit "$SHA" --json name,status,conclusion --jq '
  map(select(.name == "CI" or .name == "Unit Tests"))
  | map(select(.status != "completed" or .conclusion != "success"))
  | if length == 0 then "green" else "REQUIRED CI NOT green — abort" end'
```

`green` = proceed. Anything else means abort.

### 1.3 Run the pre-flight script

```bash
bin/pre-deploy-check
```

Gates it enforces (see `bin/pre-deploy-check` source for details):

- `.kamal/secrets` has non-empty values for `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `KAMAL_REGISTRY_PASSWORD`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`.
- `ADMIN_EMAIL` is not the sentinel `admin@expense-tracker.com`.
- `ADMIN_PASSWORD` is not the sentinel `AdminPassword123!`.
- `config/deploy.yml`'s `env.secret` block lists both `ADMIN_EMAIL` and `ADMIN_PASSWORD` (guardrail against someone removing them).
- **Remote reachability:** `kamal app details` succeeds (skippable via `--offline` if drafting the deploy offline).
- **Remote `AdminUser` presence:** asks the running prod container whether `admin_users` exists and, if so, whether it has ≥ 1 row. Prints a clear info line for re-deploys where the table is already dropped.
- `gh run list` says **required** workflows on `main` are green — `REQUIRED_WORKFLOWS` constant in `bin/pre-deploy-check` (currently `CI`, `Unit Tests`). Other workflows are reported as INFO but do not block. Skippable via `--skip-ci` for emergencies.
- Prints the backup command from §1.4 as a friendly nudge.

Flags:

- `--offline` — skip remote Kamal/SSH checks.
- `--skip-ci` — skip the `gh run list` gate. Only for genuine emergencies.

### 1.4 Snapshot the DB (critical — rollback depends on it)

Preferred: run from the Hetzner box directly. Use `--format=custom` so rollback can use `pg_restore --clean --if-exists` (plain-SQL restores can fail with "relation already exists" after the schema change).

```bash
ssh deploy@178.104.88.183 'bash -s' <<'EOF'
mkdir -p ~/backups
TS=$(date +%Y%m%dT%H%M%SZ)
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h personal-blog-db -U expense_tracker \
  --format=custom --no-owner --no-acl \
  -f ~/backups/pre-user-model-${TS}.dump \
  expense_tracker_production
ls -lh ~/backups/pre-user-model-${TS}.dump
EOF
```

`POSTGRES_PASSWORD` must be exported in the `deploy` user's shell on the Hetzner box, or replace the inline `PGPASSWORD="$POSTGRES_PASSWORD"` with `PGPASSWORD='...'` once.

Alternative via Kamal (piped through the app container — also custom format):

```bash
kamal app exec --reuse \
  "bash -c 'mkdir -p /rails/storage/backups && \
    PGPASSWORD=\$POSTGRES_PASSWORD pg_dump \
      -h \$POSTGRES_HOST -U \$POSTGRES_USER \
      --format=custom --no-owner --no-acl \
      -f /rails/storage/backups/pre-user-model.dump \
      expense_tracker_production'"
```

Write the timestamped path somewhere you can find it — you'll need it for rollback (§4).

### 1.5 Baseline the current prod

```bash
curl -fsS https://expense-tracker.estebansoto.dev/up && echo OK
```

If this is already failing, stop here and fix the baseline first. Don't layer a new deploy on top of a broken one.

---

## 2. Deploy (T+0)

One command, two terminals, eyes on the logs.

**Terminal 2 (open this FIRST — live logs):**

```bash
kamal app logs -f
```

**Terminal 1 (deploy driver):**

```bash
kamal deploy
```

### Expected log sequence

1. Docker image build + push to `ghcr.io/esoto/expense-tracker`.
2. `.kamal/hooks/pre-deploy` runs — should PASS. The hook blocks on pending migrations *against the running image*. If it complains here, the new image's schema is behind the DB — abort and investigate.
3. New container starts → `bin/docker-entrypoint` runs `bin/rails db:prepare`.
4. The 14-PR migration batch runs. Expect `add_*_user_id`, `backfill_*`, `make_*_not_null` triplets to log short `migrated` lines. Backfills on `expenses` and `sync_metrics` may take 1–3s depending on row count. Final migration: `20260421160000_drop_admin_users_table`.
5. Puma boots; Solid Queue supervisor + dispatcher start (`SOLID_QUEUE_IN_PUMA=true`).
6. Orchestrator cache warm-up (~15s silent period — the `readiness_delay` in `config/deploy.yml`).
7. kamal-proxy polls `/up` every 10s; cuts traffic to the new container once healthy.

**Expected total deploy time:** 2–5 minutes. **Expected downtime:** ≤ 15s during container swap (kamal-proxy handles the cutover).

### Red flags — abort and investigate

- `ActiveRecord::MigrationError: Found N ... with NULL user_id but no admin User exists` — PR 3's migration didn't run or seeded nothing. Abort:
  ```bash
  kamal app exec --interactive --reuse "bin/rails console"
  ```
- `PG::UndefinedColumn` or `PG::DuplicateColumn` — schema drift. Rollback per §4.
- Solid Queue connection-pool errors — unlikely, but verify `RAILS_MAX_THREADS: "8"` in `config/deploy.yml` hasn't been edited down.

---

## 3. Post-deploy smoke (T+1 — 5 minutes)

### 3.1 Automated checks

```bash
# Health endpoint
curl -fsS https://expense-tracker.estebansoto.dev/up && echo "OK: /up"

# Schema sanity — runs inside the just-deployed container.
# Uses `User.admin` (singular) because Rails auto-generates scope names from
# the enum value (`enum :role, { user: 0, admin: 1 }` in app/models/user.rb).
kamal app exec --reuse "bin/rails runner '
  fail unless User.count > 0
  fail unless User.admin.count > 0
  fail if ActiveRecord::Base.connection.tables.include?(\"admin_users\")
  fail unless ActiveRecord::Base.connection.columns(:expenses).map(&:name).include?(\"user_id\")
  puts %Q{users=#{User.count} admins=#{User.admin.count} admin_users_dropped=true expenses.user_id=present}
'"
```

### 3.2 Manual UI smoke (browser)

1. Visit `https://expense-tracker.estebansoto.dev/` → should redirect to `/login`.
2. Sign in with `ADMIN_EMAIL` / `ADMIN_PASSWORD` (values from `.kamal/secrets`).
3. Visit `/admin/users` → see yourself listed; role column reads `admin`; status reads `Active`.
4. Create a second user at `/admin/users/new` (role: user). Confirm the one-time password banner appears and the Copy button works.
5. Open an incognito window; sign in as the new user; visit `/admin/users` → expect redirect with "Forbidden" flash.
6. Back as admin: delete the test user.

### 3.3 iPhone Shortcut smoke

7. Open an existing Shortcut that hits `/api/v1/...` or `/api/webhooks/add_expense`. Run it. Confirm the expense lands in the feed — the token is now user-scoped but belongs to the default admin user (PR 11's backfill), so it should still work unchanged.

---

## 4. Rollback

Three cases. Pick the one that matches the failure.

### 4.1 Code rollback, schema intact

Deploy introduced a bug but the User-model schema is fine AND the rollback target is a post-unification image (i.e. one of PRs #460–#475 or later).

```bash
kamal rollback <previous-image-tag>
```

⚠️ **Do not code-only rollback to a pre-unification image after the schema cutover.** `.kamal/hooks/pre-deploy` checks `db:migrate:status` inside the *currently running* container (see `.kamal/hooks/pre-deploy:15`), so after a successful cutover the hook can pass even though the rollback image would crash against the migrated schema. Rolling back across the unification boundary requires a full DB restore — use case 4.2 instead, or roll forward with a fix.

### 4.2 Full rollback including schema

The migrations themselves broke something.

```bash
# On the Hetzner box, via ssh
ssh deploy@178.104.88.183

# Stop the app
kamal app stop

# Restore the DB (use the timestamped path from §1.4).
# --clean --if-exists drops the unification-era tables/columns before restoring.
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
  -h personal-blog-db -U expense_tracker \
  --clean --if-exists --no-owner --no-acl \
  -d expense_tracker_production \
  ~/backups/pre-user-model-<timestamp>.dump

# Rollback the image (back to local shell)
exit
kamal rollback <previous-image-tag>
kamal app start
```

Post-rollback: the DB has `admin_users` again, no `users` table, no `user_id` columns. All prior Shortcuts + admin logins work.

### 4.3 Partial failure (migrations started, ran some, crashed)

Rare but possible.

- Each migration runs in its own transaction EXCEPT the ones with `disable_ddl_transaction!` (concurrent-index migrations from PRs 4–11). If one of those fails, the partial state is recoverable: re-run
  ```bash
  kamal app exec --reuse "bin/rails db:migrate"
  ```
  and it continues from where it left off.
- If you can't make progress, restore from backup per §4.2.

---

## Note to self

- After cutover, every existing browser cookie is invalidated. Log in again at `/login` (not `/admin/login`).
- `kamal rollback` rolls the image only — the DB is NOT restored by rollback.
- The backup file from §1.4 is the only path back to the old schema. Don't skip it.
