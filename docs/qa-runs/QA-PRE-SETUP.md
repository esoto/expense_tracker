# QA Sweep Pre-Setup Guide

Run these steps **in order** before launching QA agents. Each step has exact commands to copy-paste.

**App directory:** `/Users/esoto/development/expense_tracker`
**Login credentials:** `admin@expense-tracker.com` / `AdminPassword123!`
**Login URL:** `http://localhost:3000/admin/login`

---

## Step 1: Kill and Restart Puma

**Why:** Rack::Attack stores rate-limit counters in Puma's in-memory MemoryStore. After 10 login attempts in 15 minutes, all further logins return 429 Too Many Requests. Restarting Puma resets ALL counters. There is no way to clear them externally — `rails runner` runs in a separate process and cannot access Puma's memory.

**Rack::Attack throttles configured (11 total):** `req/ip`, `logins/ip`, `logins/email`, `password-reset/ip`, `api/ip`, `patterns/test/ip`, `patterns/import/ip`, `exports/ip`, `statistics/ip`, `sidekiq-web/ip`, `sidekiq-web-write/ip`

```bash
# From the project root:
cd /Users/esoto/development/expense_tracker

# Kill any existing server on port 3000
kill $(lsof -ti :3000) 2>/dev/null

# Wait for it to die
sleep 2

# Verify port is free
lsof -i :3000 || echo "Port 3000 is free"

# Start fresh server in background
bin/rails server -d

# Wait for boot and verify
sleep 3
curl -s -o /dev/null -w "HTTP %{http_code}" http://localhost:3000/admin/login
# Expected output: HTTP 200
```

---

## Step 2: Raise Rate Limits for QA

**Why:** With 6 QA agents running in parallel, even with session reuse, unexpected session expiry (Turbo nav bugs, cookie issues) forces re-login. 10 attempts across 6 agents = locked out in minutes.

**File to edit:** `config/initializers/rack_attack.rb`

**What to change:** Find ALL `throttle` calls with `limit:` and raise them to 1000. The key ones:

```bash
# Find all throttle limits
grep -n "limit:" config/initializers/rack_attack.rb
```

**Exact sed commands to raise all limits:**
```bash
cd /Users/esoto/development/expense_tracker
sed -i '' 's/limit: 10,/limit: 1000,/g' config/initializers/rack_attack.rb
sed -i '' 's/limit: 5,/limit: 1000,/g' config/initializers/rack_attack.rb
sed -i '' 's/limit: 3,/limit: 1000,/g' config/initializers/rack_attack.rb
sed -i '' 's/limit: 20,/limit: 1000,/g' config/initializers/rack_attack.rb
sed -i '' 's/limit: 60,/limit: 1000,/g' config/initializers/rack_attack.rb
sed -i '' 's/limit: 100,/limit: 1000,/g' config/initializers/rack_attack.rb

# Verify the changes
grep "limit:" config/initializers/rack_attack.rb
# Expected: all limits should show 1000
```

**CRITICAL:** After QA finishes, revert this:
```bash
git checkout config/initializers/rack_attack.rb
```

Then restart Puma again (Step 1) so the reverted limits take effect.

---

## Step 3: Pre-Seed Required Test Data

**Why:** QA scenarios require specific data to exist. Without it, scenarios are marked BLOCKED.

### Current Data State (as of 2026-03-27)

| Data | Count | Minimum for QA | Status |
|------|-------|----------------|--------|
| AdminUser | 1 (`admin@expense-tracker.com`) | 1 | OK |
| EmailAccount | 2 (gmail/BAC, active) | 1 | OK |
| Expense | 78 (all not_deleted) | >50 (for pagination) | OK |
| Category | 22 | >5 | OK |
| CategorizationPattern | 127 | >10 | OK |
| Budget | 1 (monthly, Alimentación) | 3+ (different periods) | NEEDS MORE |
| SyncSession | 2 (both failed) | 1 completed + 1 failed | NEEDS COMPLETED |
| CompositePattern | 0 | 1+ | NEEDS CREATION |
| ApiToken | 4 (token_digest stored, not plaintext) | 1 with known value | SEE STEP 4 |

### Create Missing Data

```bash
cd /Users/esoto/development/expense_tracker

bin/rails runner "
  ea = EmailAccount.first
  raise 'No EmailAccount! Run db:seed first' unless ea

  # --- BUDGETS (need 3 with different periods) ---
  existing = Budget.count
  puts \"Budgets before: #{existing}\"

  unless Budget.exists?(period: 'weekly')
    Budget.create!(
      name: 'Presupuesto Semanal Transporte',
      category: Category.find_by(name: 'Transporte') || Category.first,
      email_account: ea,
      amount: 50000,
      period: 'weekly',
      currency: 'CRC',
      start_date: Date.today.beginning_of_week,
      warning_threshold: 70,
      critical_threshold: 90,
      active: true
    )
    puts '  Created weekly budget (Transporte)'
  end

  unless Budget.exists?(period: 'yearly')
    Budget.create!(
      name: 'Presupuesto Anual Entretenimiento',
      category: Category.find_by(name: 'Entretenimiento') || Category.second,
      email_account: ea,
      amount: 2000000,
      period: 'yearly',
      currency: 'CRC',
      start_date: Date.today.beginning_of_year,
      warning_threshold: 70,
      critical_threshold: 90,
      active: true
    )
    puts '  Created yearly budget (Entretenimiento)'
  end

  # Create one INACTIVE budget for testing toggle
  unless Budget.exists?(active: false)
    Budget.create!(
      name: 'Presupuesto Inactivo Test',
      category: Category.find_by(name: 'Servicios') || Category.third,
      email_account: ea,
      amount: 100000,
      period: 'monthly',
      currency: 'CRC',
      start_date: Date.today.beginning_of_month,
      warning_threshold: 70,
      critical_threshold: 90,
      active: false
    )
    puts '  Created inactive budget (Servicios)'
  end

  puts \"Budgets after: #{Budget.count}\"

  # --- SYNC SESSIONS (need at least 1 completed) ---
  puts \"\\nSync sessions before: #{SyncSession.count} (completed: #{SyncSession.where(status: 'completed').count})\"

  unless SyncSession.exists?(status: 'completed')
    SyncSession.create!(
      status: 'completed',
      started_at: 1.hour.ago,
      completed_at: 30.minutes.ago,
      total_emails: 15,
      processed_emails: 15,
      detected_expenses: 5,
      errors_count: 0,
      session_token: SecureRandom.hex(16),
      metadata: { source: 'qa_seed', duration_seconds: 1800 }
    )
    puts '  Created completed sync session'
  end

  # Create an in-progress session for testing
  unless SyncSession.exists?(status: 'in_progress')
    SyncSession.create!(
      status: 'in_progress',
      started_at: 5.minutes.ago,
      total_emails: 10,
      processed_emails: 3,
      detected_expenses: 1,
      errors_count: 0,
      session_token: SecureRandom.hex(16)
    )
    puts '  Created in-progress sync session'
  end

  puts \"Sync sessions after: #{SyncSession.count} (completed: #{SyncSession.where(status: 'completed').count})\"

  # --- COMPOSITE PATTERNS (need at least 1) ---
  puts \"\\nComposite patterns before: #{CompositePattern.count}\"

  if CompositePattern.count == 0
    cp = CompositePattern.create!(
      name: 'QA Test Composite',
      description: 'Combines merchant + keyword for testing',
      category: Category.find_by(name: 'Supermercado') || Category.first,
      logic_operator: 'AND',
      active: true,
      confidence_threshold: 0.8
    )
    # Add component patterns if the association exists
    if cp.respond_to?(:pattern_ids=)
      cp.update(pattern_ids: CategorizationPattern.active.limit(2).pluck(:id))
    end
    puts '  Created composite pattern'
  end

  puts \"Composite patterns after: #{CompositePattern.count}\"

  # --- VERIFY EXPENSE DATA FOR PAGINATION ---
  puts \"\\nExpenses: #{Expense.not_deleted.count} (page 1: #{Expense.not_deleted.order(transaction_date: :desc).limit(50).count}, page 2: #{Expense.not_deleted.order(transaction_date: :desc).offset(50).limit(50).count})\"
  puts \"Expense statuses: #{Expense.not_deleted.group(:status).count.inspect}\"
  puts \"Categories used: #{Expense.not_deleted.where.not(category_id: nil).distinct.count(:category_id)}\"
"
```

**Expected output:** All data created, no errors.

---

## Step 4: Create a Known API Token

**Why:** The `ApiToken` model stores `token_digest` (hashed), not plaintext. Existing tokens can't be read back. We need to create a fresh one and capture the plaintext value.

**How ApiToken auth works:** API requests send `Authorization: Token <plaintext>`. The controller hashes the token and looks up the matching `token_digest`.

```bash
cd /Users/esoto/development/expense_tracker

bin/rails runner "
  # Create a new token and capture the plaintext
  token = ApiToken.create!(name: 'QA Sweep #{Date.today}', active: true)

  # The plaintext is only available right after creation
  # Check how the model generates/returns it
  puts 'ApiToken created:'
  puts \"  ID: #{token.id}\"
  puts \"  Name: #{token.name}\"
  puts \"  Attributes: #{token.attributes.keys.join(', ')}\"

  # Try common accessor patterns
  if token.respond_to?(:token)
    puts \"  Plaintext token: #{token.token}\"
    puts \"  Use header: Authorization: Token #{token.token}\"
  elsif token.respond_to?(:raw_token)
    puts \"  Plaintext token: #{token.raw_token}\"
  else
    puts '  WARNING: Could not find plaintext accessor. Check the ApiToken model.'
    puts '  You may need to read app/models/api_token.rb to find the accessor method.'
  end
"
```

**Save the token value** — write it down or export it:
```bash
export QA_API_TOKEN="<paste token value here>"

# Test it works:
curl -s -H "Authorization: Token $QA_API_TOKEN" http://localhost:3000/api/health | head -20
# Expected: JSON response with health status (may be 503 if cache not warmed — that's OK)
```

---

## Step 5: Build Tailwind CSS

**Why:** The worktree and dev server may not have compiled CSS. Without it, the UI renders unstyled and Playwright assertions on CSS classes fail.

```bash
cd /Users/esoto/development/expense_tracker
bin/rails tailwindcss:build

# Expected output:
# ≈ tailwindcss v4.x.x
# Done in XXXms
```

---

## Step 6: Warm the Pattern Cache

**Why:** `/api/health` and `/api/health/ready` return 503 if `pattern_cache` has 0 entries. This causes false QA failures on health check scenarios.

```bash
cd /Users/esoto/development/expense_tracker

bin/rails runner "
  cache = Services::Categorization::PatternCache.instance
  cache.warm_cache
  puts \"Pattern cache warmed: #{cache.size} entries\"
rescue NoMethodError => e
  puts \"PatternCache doesn't have warm_cache method: #{e.message}\"
  puts 'Try alternative: Services::Categorization::PatternCache.new.load_patterns'
rescue => e
  puts \"Cache warm failed (non-blocking): #{e.class}: #{e.message}\"
  puts 'Health endpoints will return 503 — mark those scenarios as environment-specific.'
"
```

**Then restart Puma** so the warmed cache is in the server process:
```bash
kill $(lsof -ti :3000) 2>/dev/null && sleep 2 && bin/rails server -d
sleep 3
curl -s http://localhost:3000/api/health | python3 -m json.tool | head -5
# Expected: "healthy": true (or at least no 500 error)
```

---

## Step 7: Create Screenshots Folder

```bash
mkdir -p /Users/esoto/development/expense_tracker/docs/qa-runs/$(date +%Y-%m-%d)/screenshots
echo "Screenshots folder ready at: docs/qa-runs/$(date +%Y-%m-%d)/screenshots/"
```

---

## Step 8: Copy Playbook Templates

The original playbooks in `docs/plans/` are templates. Copy them for this run:

```bash
DATE=$(date +%Y-%m-%d)
DEST=/Users/esoto/development/expense_tracker/docs/qa-runs/$DATE

mkdir -p $DEST

# Copy and split large files for agent context limits
for f in /Users/esoto/development/expense_tracker/docs/plans/qa-playbook-group-*.md; do
  cp "$f" "$DEST/$(basename $f)"
done

# Split Group C+D (118 scenarios, too large for one agent)
csplit -f "$DEST/cd-part-" -n 1 "$DEST/qa-playbook-group-cd-bulk-email-sync.md" '/^## Email Accounts/' 2>/dev/null
mv "$DEST/cd-part-0" "$DEST/qa-playbook-group-c-bulk-ml.md"
mv "$DEST/cd-part-1" "$DEST/qa-playbook-group-d-email-sync.md"

# Split Group E+F+G (126 scenarios, too large for one agent)
csplit -f "$DEST/efg-part-" -n 1 "$DEST/qa-playbook-group-efg-admin-api-budget.md" '/^## Budget Management/' 2>/dev/null
mv "$DEST/efg-part-0" "$DEST/qa-playbook-group-e-admin-analytics.md"
mv "$DEST/efg-part-1" "$DEST/qa-playbook-group-fg-budget-api.md"

echo "Playbooks ready:"
ls -la $DEST/qa-playbook-group-{a,b,c,d,e,fg}*.md
```

---

## Step 9: Agent Instructions

### Each Agent Must:

1. **Log in ONCE at the start** via Playwright:
   - Navigate to `http://localhost:3000/admin/login`
   - Fill email: `admin@expense-tracker.com`
   - Fill password: `AdminPassword123!`
   - Click "Iniciar Sesión"
   - **Do NOT log in again** unless session expires. Re-logins consume rate limit.

2. **Set viewport before navigating** (not after):
   - Desktop: `browser_resize(width: 1280, height: 800)`
   - Mobile: `browser_resize(width: 375, height: 812)`

3. **Use `browser_snapshot`** for content verification (fast, returns DOM tree)

4. **Use `browser_take_screenshot`** ONLY on failures (saves to `screenshots/` folder)

5. **Use `curl` for API scenarios** (not Playwright):
   ```bash
   curl -s -H "Authorization: Token $QA_API_TOKEN" http://localhost:3000/api/endpoint
   ```

6. **Mark results in the playbook file:**
   - `[x]` for passing criteria
   - `[ ]` with `**FAILED:** actual behavior` for failures
   - `[ ]` with `**BLOCKED:** reason` for untestable scenarios

7. **Add a summary at the top** when done:
   ```markdown
   ## Results Summary
   **Date:** YYYY-MM-DD
   **Total:** X | **Pass:** X | **Fail:** X | **Blocked:** X
   ```

---

## Final Verification Checklist

Run this to confirm everything is ready:

```bash
cd /Users/esoto/development/expense_tracker

echo "=== QA READINESS CHECK ==="
echo ""

# 1. Server running?
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/admin/login 2>/dev/null)
echo "1. Server: $([ "$HTTP" = "200" ] && echo "OK (HTTP $HTTP)" || echo "FAIL (HTTP $HTTP)")"

# 2. Login works?
echo "2. Login: test manually at http://localhost:3000/admin/login"

# 3. Data check
bin/rails runner "
  checks = {
    'AdminUser' => AdminUser.count >= 1,
    'EmailAccount' => EmailAccount.count >= 1,
    'Expenses (>50)' => Expense.not_deleted.count > 50,
    'Categories (>5)' => Category.count > 5,
    'Patterns (>10)' => CategorizationPattern.count > 10,
    'Budgets (>2)' => Budget.count > 2,
    'SyncSession completed' => SyncSession.where(status: 'completed').exists?,
    'SyncSession failed' => SyncSession.where(status: 'failed').exists?
  }
  checks.each do |name, ok|
    puts \"3. #{name}: #{ok ? 'OK' : 'MISSING'}\"
  end
" 2>&1

# 4. Tailwind built?
echo "4. Tailwind: $([ -f app/assets/builds/tailwind.css ] && echo 'OK' || echo 'NEEDS BUILD')"

# 5. Screenshots folder?
DATE=$(date +%Y-%m-%d)
echo "5. Screenshots: $([ -d docs/qa-runs/$DATE/screenshots ] && echo 'OK' || echo 'NEEDS CREATION')"

# 6. Playbooks copied?
echo "6. Playbooks: $(ls docs/qa-runs/$DATE/qa-playbook-group-{a,b,c,d,e,fg}*.md 2>/dev/null | wc -l | tr -d ' ') files ready"

echo ""
echo "=== All checks should show OK ==="
```

---

## Post-Run Cleanup

```bash
cd /Users/esoto/development/expense_tracker

# 1. Revert rate limit changes
git checkout config/initializers/rack_attack.rb

# 2. Drop orphaned test databases (from any worktrees)
psql -U esoto -d postgres -t -c "SELECT datname FROM pg_database WHERE datname LIKE 'expense_tracker_test_%';" | while read db; do
  db=$(echo "$db" | xargs)
  [ -n "$db" ] && psql -U esoto -d postgres -c "DROP DATABASE \"$db\";" && echo "Dropped $db"
done

# 3. Clean up worktrees
git worktree list | grep -v "main" | awk '{print $1}' | while read wt; do
  git worktree remove "$wt" --force 2>/dev/null && echo "Removed $wt"
done

# 4. Restart server with original config
kill $(lsof -ti :3000) 2>/dev/null && sleep 2 && bin/rails server -d
echo "Server restarted with original config"
```
