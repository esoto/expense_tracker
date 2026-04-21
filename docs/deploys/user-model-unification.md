# Deploy Runbook — User-Model Unification Cutover

One-time runbook for the 14-PR User-model unification deploy (PRs #460–#475, merged to `main` on 2026-04-21 at commit `d727375`). After this deploy ships and smokes green, this file can stay as a reference for future operators.

Three risk surfaces you're dealing with:

1. **First-boot data migration.** `db/migrate/20260421130100_create_default_user_from_admin_users.rb` reads `admin_users` rows and creates `User` rows. PR 14's `drop_admin_users_table` runs later in the same batch — the drop is safe because rows are already copied, but the first deploy MUST have at least one `admin_users` row when migrations start.
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
gh run list --branch main --limit 1 --json conclusion,status \
  --jq '.[0] | select(.conclusion != "success") | "CI NOT green — abort"'
```

No output = green. Any output means abort.

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
- `gh run list` says CI on `main` is green (skippable via `--skip-ci` for emergencies).
- Prints the backup command from §1.4 as a friendly nudge.

Flags:

- `--offline` — skip remote Kamal/SSH checks.
- `--skip-ci` — skip the `gh run list` gate. Only for genuine emergencies.

### 1.4 Snapshot the DB (critical — rollback depends on it)

Preferred: run from the Hetzner box directly.

```bash
ssh deploy@178.104.88.183 \
  "pg_dump -h personal-blog-db -U expense_tracker expense_tracker_production \
     | gzip > ~/backups/pre-user-model-$(date +%Y%m%dT%H%M%SZ).sql.gz"
```

Alternative via Kamal (piped through the app container):

```bash
kamal app exec --reuse \
  "bash -c 'pg_dump -h \$POSTGRES_HOST -U \$POSTGRES_USER expense_tracker_production' \
  > /rails/storage/backups/pre-user-model.sql"
```

Verify the file exists and is non-empty:

```bash
ssh deploy@178.104.88.183 "ls -lh ~/backups/pre-user-model-*.sql.gz | tail -1"
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

# Schema sanity — runs inside the just-deployed container
kamal app exec --reuse "bin/rails runner '
  fail unless User.count > 0
  fail unless User.admins.count > 0
  fail if ActiveRecord::Base.connection.tables.include?(\"admin_users\")
  fail unless ActiveRecord::Base.connection.columns(:expenses).map(&:name).include?(\"user_id\")
  puts %Q{users=#{User.count} admins=#{User.admins.count} admin_users_dropped=true expenses.user_id=present}
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

Deploy introduced a bug but the User-model schema is fine.

```bash
kamal rollback <previous-image-tag>
```

`.kamal/hooks/pre-deploy` will BLOCK this because the old image is behind the current schema. Override with `kamal deploy --skip-hooks` ONLY if you also restore the DB (case 4.2).

### 4.2 Full rollback including schema

The migrations themselves broke something.

```bash
# On the Hetzner box, via ssh
ssh deploy@178.104.88.183

# Stop the app
kamal app stop

# Restore the DB (use the timestamped path from §1.4)
gunzip -c ~/backups/pre-user-model-<timestamp>.sql.gz \
  | psql -h personal-blog-db -U expense_tracker expense_tracker_production

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
