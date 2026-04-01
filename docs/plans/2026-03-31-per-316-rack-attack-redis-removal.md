# PER-316: Rack::Attack Redis Branch Removal

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the conditional Redis cache store branch from Rack::Attack so it uses `Rails.cache` unconditionally, aligning with the Solid Cache migration (PER-312 epic).

**Architecture:** Replace the 6-line conditional (lines 10-16) in `rack_attack.rb` with a single `Rails.cache` assignment. Add a spec verifying no Redis branch exists, following the existing pattern of reading the initializer source.

**Tech Stack:** Rails 8.1.2, Rack::Attack, Solid Cache, RSpec

---

### Task 1: Write failing test for cache store configuration

**Files:**
- Modify: `spec/initializers/rack_attack_spec.rb:115` (insert before `describe "middleware loading"`)

**Step 1: Write the failing test**

Add this test block before the `describe "middleware loading"` block (line 115):

```ruby
describe "cache store configuration" do
  it "uses Rails.cache unconditionally without Redis branching" do
    initializer_path = Rails.root.join("config/initializers/rack_attack.rb")
    content = File.read(initializer_path)

    # Must use Rails.cache directly, no Redis conditional
    expect(content).to include("Rack::Attack.cache.store = Rails.cache")
    expect(content).not_to include("RedisCacheStore")
    expect(content).not_to include('ENV["REDIS_URL"]')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/initializers/rack_attack_spec.rb --tag unit -v`

Expected: FAIL — the initializer currently contains `RedisCacheStore` and `ENV["REDIS_URL"]`.

### Task 2: Remove Redis branch from initializer

**Files:**
- Modify: `config/initializers/rack_attack.rb:10-16`

**Step 3: Replace the conditional block**

Replace lines 10-16:
```ruby
  # Store configuration in Redis if available, otherwise use in-memory cache
  if ENV["REDIS_URL"].present?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])
  else
    # Use Rails cache for development/testing
    Rack::Attack.cache.store = Rails.cache
  end
```

With:
```ruby
  # Use Rails.cache (Solid Cache in production, memory store in dev)
  Rack::Attack.cache.store = Rails.cache
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/initializers/rack_attack_spec.rb --tag unit -v`

Expected: ALL PASS (including the new cache store configuration test).

**Step 5: Run full pre-commit checks**

Run: `bundle exec rubocop config/initializers/rack_attack.rb spec/initializers/rack_attack_spec.rb && bundle exec brakeman -q && bundle exec rspec --tag unit`

Expected: All green — no RuboCop offenses, no Brakeman warnings, all unit tests pass.

### Task 3: Commit

**Step 6: Commit the changes**

```bash
git add config/initializers/rack_attack.rb spec/initializers/rack_attack_spec.rb
git commit -m "🐛 fix(config): remove Redis branch from Rack::Attack, use Rails.cache unconditionally (PER-316)"
```
