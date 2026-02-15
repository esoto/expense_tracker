# Security Audit Report - Expense Tracker Application

**Audit Date:** 2026-02-14
**Auditor:** Security Auditor (Automated + Manual Review)
**Application:** Rails 8.1 Expense Tracker with PostgreSQL, ActionCable, Solid Queue
**Scope:** All controllers, models, services, channels, initializers, and configuration files
**Brakeman Status:** Could not run (gem dependency mismatch) -- manual review performed

---

## Summary Table

| # | Severity | Finding | Epic/Area | File | Status |
|---|----------|---------|-----------|------|--------|
| S-01 | **CRITICAL** | Multiple controllers missing authentication entirely | All Epics | Multiple controllers | NEW |
| S-02 | **CRITICAL** | SyncAuthorization always returns `true` (placeholder) | Epic 1 | `concerns/sync_authorization.rb` | NEW |
| S-03 | **CRITICAL** | Admin login CSRF protection disabled | Admin Auth | `admin/sessions_controller.rb:6` | NEW |
| S-04 | **CRITICAL** | API v1 CategoriesController inherits ApplicationController, not Api::BaseController -- no API auth | Categorization | `api/v1/categories_controller.rb` | NEW |
| S-05 | **HIGH** | Queue controller dev/test environment bypass | Epic 1 | `api/queue_controller.rb:262` | KNOWN |
| S-06 | **HIGH** | Queue controller admin_key comparison is not timing-safe | Epic 1 | `api/queue_controller.rb:258` | NEW |
| S-07 | **HIGH** | Sidekiq Web default credentials in production | Infrastructure | `config/routes.rb:16` | NEW |
| S-08 | **HIGH** | MonitoringController uses plaintext token lookup instead of BCrypt | Epic 2 | `api/monitoring_controller.rb:49` | NEW |
| S-09 | **HIGH** | Client errors endpoint completely unauthenticated -- DoS vector | Epic 1 | `api/client_errors_controller.rb` | NEW |
| S-10 | **HIGH** | WebSocket connection accepts fallback-generated session IDs | Epic 1 | `application_cable/connection.rb:58` | NEW |
| S-11 | **HIGH** | QueueChannel broadcasts to all subscribers without user scoping | Epic 1 | `channels/queue_channel.rb` | NEW |
| S-12 | **HIGH** | EmailAccountsController has no authentication | All Epics | `email_accounts_controller.rb` | NEW |
| S-13 | **HIGH** | `html_safe` used with user-influenced data in helpers | Epic 3 | `helpers/accessibility_helper.rb`, `helpers/analytics_helper.rb` | NEW |
| S-14 | **HIGH** | PatternManagementController `require_pattern_management_permission` always returns `true` | Categorization | `admin/pattern_management_controller.rb:64` | NEW |
| S-15 | **MEDIUM** | Content Security Policy is commented out globally | All Epics | `config/initializers/content_security_policy.rb` | NEW |
| S-16 | **MEDIUM** | Rack::Attack only enabled in production/staging, not development | All Epics | `config/initializers/rack_attack.rb:275` | NEW |
| S-17 | **MEDIUM** | SyncConflictsController has no authentication | Epic 1 | `sync_conflicts_controller.rb` | NEW |
| S-18 | **MEDIUM** | SyncPerformanceController has no authentication | Epic 1 | `sync_performance_controller.rb` | NEW |
| S-19 | **MEDIUM** | CategoriesController (non-API) has no authentication | Epic 3 | `categories_controller.rb` | NEW |
| S-20 | **MEDIUM** | BudgetsController has no user-scoped authentication | Epic 3 | `budgets_controller.rb` | NEW |
| S-21 | **MEDIUM** | UndoHistoriesController has no authentication | Epic 3 | `undo_histories_controller.rb` | NEW |
| S-22 | **MEDIUM** | API health endpoint exposes internal system metrics without auth | Epic 2 | `api/health_controller.rb` | NEW |
| S-23 | **MEDIUM** | Admin audit logging uses `to_unsafe_h` | Admin | `admin/base_controller.rb:35` | NEW |
| S-24 | **MEDIUM** | `announce_to_screen_reader` uses `raw` with user-controllable message | Epic 3 | `helpers/accessibility_helper.rb:73` | NEW |
| S-25 | **LOW** | `current_user_email_accounts` returns all accounts (no user scoping) | Epic 3 | `expenses_controller.rb:571` | NEW |
| S-26 | **LOW** | Monitoring health endpoint `health` has no authentication | Epic 2 | `api/monitoring_controller.rb:23` | NEW |
| S-27 | **LOW** | ApiToken authentication result cached in Rails.cache | API | `models/api_token.rb:43` | NEW |
| S-28 | **LOW** | Rate limiting test environment bypass | All Epics | `config/initializers/rack_attack.rb:7` | NEW |

---

## Detailed Findings

---

### S-01: CRITICAL - Multiple Controllers Missing Authentication Entirely

**Severity:** CRITICAL
**Epic Affected:** All Epics
**Files:**
- `/Users/esoto/development/expense_tracker/app/controllers/email_accounts_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/sync_conflicts_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/sync_performance_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/categories_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/budgets_controller.rb`
- `/Users/esoto/development/expense_tracker/app/controllers/undo_histories_controller.rb`

**Description:**
Multiple controllers inherit from `ApplicationController` but do NOT include the `Authentication` concern. `ApplicationController` itself does not enforce authentication -- it only configures CSRF behavior. This means these controllers are fully accessible to **unauthenticated users**.

The following controllers include `Authentication` and are protected:
- `ExpensesController`
- `BulkCategorizationsController`
- `BulkCategorizationActionsController`

The following controllers are completely unprotected:
- `EmailAccountsController` -- CRUD on email accounts including passwords
- `SyncConflictsController` -- resolve/undo sync conflicts
- `SyncPerformanceController` -- view performance metrics
- `CategoriesController` -- list all categories
- `BudgetsController` -- CRUD on budgets
- `UndoHistoriesController` -- undo operations

**Reproduction Steps:**
1. Without any session or credentials, visit `/email_accounts`
2. Create, edit, or delete email accounts without authentication
3. Visit `/sync_conflicts` to see all sync conflicts
4. Visit `/budgets` to create/edit/delete budgets

**Recommended Fix:**
Add `include Authentication` to all controllers that should require a logged-in user, or add a `before_action :authenticate_user!` in `ApplicationController` and explicitly skip it only for controllers that should be public.

```ruby
# Option A: Add to each controller
class EmailAccountsController < ApplicationController
  include Authentication
  # ...
end

# Option B: Add to ApplicationController (preferred)
class ApplicationController < ActionController::Base
  include Authentication
  # Controllers that need to be public skip authentication explicitly
end
```

---

### S-02: CRITICAL - SyncAuthorization Always Returns True (Placeholder)

**Severity:** CRITICAL
**Epic Affected:** Epic 1 (Sync Status Interface)
**File:** `/Users/esoto/development/expense_tracker/app/controllers/concerns/sync_authorization.rb`
**Lines:** 21-25 and 39-43

**Description:**
Both `sync_access_allowed?` and `sync_session_owner?` are placeholder methods that unconditionally return `true`. This means:
- ANY user (or unauthenticated visitor) can access ANY sync session
- There is no ownership check on sync sessions
- The `authorize_sync_session_owner!` check is completely bypassed

```ruby
def sync_access_allowed?
  # This is a placeholder - in production, check actual user permissions
  true # TODO: Implement real authorization logic
end

def sync_session_owner?
  # Placeholder - check if current user owns the sync session
  true # TODO: Implement real ownership check
end
```

**Reproduction Steps:**
1. Obtain the ID of any sync session
2. Visit `/sync_sessions/:id` as any user or without authentication
3. Cancel or retry any sync session regardless of ownership

**Recommended Fix:**
Implement actual authorization logic:
```ruby
def sync_access_allowed?
  user_signed_in?
end

def sync_session_owner?
  @sync_session.user_id == current_user.id
end
```

---

### S-03: CRITICAL - Admin Login CSRF Protection Disabled

**Severity:** CRITICAL
**Epic Affected:** Admin Authentication
**File:** `/Users/esoto/development/expense_tracker/app/controllers/admin/sessions_controller.rb`
**Line:** 6

**Description:**
The admin login controller skips CSRF token verification for the `create` action:

```ruby
skip_before_action :verify_authenticity_token, only: [ :create ]
```

This allows an attacker to craft a malicious page that submits a login form to the application on behalf of a victim. Combined with the fact that `ApplicationController` uses `protect_from_forgery with: :null_session` for JSON requests, this creates a login CSRF vulnerability.

A login CSRF attack allows an attacker to log the victim into the attacker's account, potentially capturing sensitive data entered by the victim.

**Reproduction Steps:**
1. Create a malicious HTML page with a form that POSTs to `/admin/login`
2. Include attacker's credentials in the form
3. Trick an admin into visiting the page
4. The admin is now logged into the attacker's account

**Recommended Fix:**
Remove the `skip_before_action` line. The login form should include a CSRF token like all other forms:
```ruby
# Remove this line:
# skip_before_action :verify_authenticity_token, only: [ :create ]
```

---

### S-04: CRITICAL - API v1 CategoriesController Has No API Authentication

**Severity:** CRITICAL
**Epic Affected:** Categorization
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/v1/categories_controller.rb`

**Description:**
The `Api::V1::CategoriesController` inherits from `ApplicationController` instead of `Api::V1::BaseController` (which inherits from `Api::BaseController` and enforces API token authentication). This means the endpoint `/api/v1/categories` is completely unauthenticated and publicly accessible.

```ruby
module Api
  module V1
    class CategoriesController < ApplicationController  # Should be BaseController
      skip_before_action :verify_authenticity_token
      # No authentication whatsoever
```

All other API v1 controllers (`PatternsController`, `CategorizationController`) correctly inherit from `Api::V1::BaseController` and require API token authentication.

**Reproduction Steps:**
1. Send a GET request to `/api/v1/categories` without any authentication
2. All categories are returned

**Recommended Fix:**
```ruby
class CategoriesController < BaseController  # Use Api::V1::BaseController
  # Remove the skip_before_action since BaseController handles it
```

---

### S-05: HIGH - Queue Controller Dev/Test Environment Bypass (KNOWN)

**Severity:** HIGH
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/queue_controller.rb`
**Line:** 262

**Description:**
This is a KNOWN issue documented in `docs/issues/authentication-security-gap.md`. The queue controller allows full access in development and test environments:

```ruby
return true if Rails.env.development? || Rails.env.test?
```

This could be exploited if `RAILS_ENV` is misconfigured in production.

---

### S-06: HIGH - Queue Controller Admin Key Comparison Not Timing-Safe

**Severity:** HIGH
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/queue_controller.rb`
**Line:** 258

**Description:**
The admin key comparison uses Ruby's `==` operator instead of `ActiveSupport::SecurityUtils.secure_compare`:

```ruby
return true if provided_key == admin_key
```

This is vulnerable to timing attacks where an attacker can determine the admin key character by character by measuring response times.

Note: The Sidekiq Web config in `routes.rb` correctly uses `secure_compare`, but the queue controller does not.

**Recommended Fix:**
```ruby
return true if ActiveSupport::SecurityUtils.secure_compare(provided_key.to_s, admin_key.to_s)
```

---

### S-07: HIGH - Sidekiq Web Default Credentials in Production

**Severity:** HIGH
**Epic Affected:** Infrastructure
**File:** `/Users/esoto/development/expense_tracker/config/routes.rb`
**Line:** 15-16

**Description:**
The Sidekiq Web UI uses environment variables for credentials with insecure defaults:

```ruby
ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SIDEKIQ_WEB_USERNAME", "admin")) &&
ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SIDEKIQ_WEB_PASSWORD", "change_me_in_production"))
```

If `SIDEKIQ_WEB_PASSWORD` is not set, the default password `"change_me_in_production"` is used, granting full access to the Sidekiq dashboard which can manage background jobs, view job arguments (potentially containing sensitive data), and clear/retry jobs.

**Recommended Fix:**
Raise an error at boot if these environment variables are not set in production:
```ruby
if Rails.env.production?
  raise "SIDEKIQ_WEB_USERNAME must be set" unless ENV["SIDEKIQ_WEB_USERNAME"].present?
  raise "SIDEKIQ_WEB_PASSWORD must be set" unless ENV["SIDEKIQ_WEB_PASSWORD"].present?
end
```

---

### S-08: HIGH - MonitoringController Uses Plaintext Token Lookup

**Severity:** HIGH
**Epic Affected:** Epic 2
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/monitoring_controller.rb`
**Line:** 49

**Description:**
The `authenticate_api_request` method searches for API tokens using a plaintext value directly against the database:

```ruby
def authenticate_api_request
  api_token = request.headers["X-API-Token"] || params[:api_token]
  unless api_token.present? && ApiToken.active.where(token: api_token).exists?
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
```

Two problems:
1. `ApiToken` does not have a `token` column -- tokens are stored as BCrypt digests in `token_digest`. This query will always fail or match nothing.
2. If a `token` column did exist, this would be comparing plaintext tokens, bypassing the BCrypt-based `ApiToken.authenticate` method used everywhere else.
3. The token is also accepted as a query parameter (`params[:api_token]`), which means it appears in server logs and browser history.

**Recommended Fix:**
Use the standard `ApiToken.authenticate` method:
```ruby
def authenticate_api_request
  token = request.headers["Authorization"]&.remove("Bearer ")
  unless token.present? && ApiToken.authenticate(token)
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
```

---

### S-09: HIGH - Client Errors Endpoint Completely Unauthenticated

**Severity:** HIGH
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/client_errors_controller.rb`

**Description:**
The client errors endpoint accepts any POST request without authentication and writes directly to the database (if `ClientError` model exists) and logs the full payload. This is a Denial of Service (DoS) vector:

```ruby
class ClientErrorsController < ApplicationController
  skip_before_action :verify_authenticity_token
  # No authentication at all

  def create
    # Logs arbitrary data from any source
    Rails.logger.error "[CLIENT_ERROR] Details: #{error_data.to_json}"
    # Writes to database if model exists
    if defined?(ClientError)
      ClientError.create!(error_data)
    end
```

An attacker can flood this endpoint with arbitrary data, filling up logs and potentially the database.

**Recommended Fix:**
- Add rate limiting specific to this endpoint
- Validate and sanitize input data
- Limit payload size
- Consider requiring a session token or CSRF token

---

### S-10: HIGH - WebSocket Connection Accepts Fallback-Generated Session IDs

**Severity:** HIGH
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/channels/application_cable/connection.rb`
**Line:** 58

**Description:**
When the session cookie is a Hash but does not contain a `session_id` key, the code generates a random session ID using `SecureRandom.hex(16)` and treats the connection as authenticated:

```ruby
def extract_session_id(session_data)
  case session_data
  when Hash
    session_data["session_id"] || session_data[:session_id] || SecureRandom.hex(16)
  # ...
```

This means any request with a Hash-like cookie structure (even if it doesn't contain a valid session) will be accepted as authenticated. The generated random session ID will pass the `rails_session_id.present?` check in `find_verified_session`.

**Recommended Fix:**
Remove the `SecureRandom.hex(16)` fallback and return `nil` when no session ID is found:
```ruby
session_data["session_id"] || session_data[:session_id]  # Remove || SecureRandom.hex(16)
```

---

### S-11: HIGH - QueueChannel Broadcasts to All Subscribers Without User Scoping

**Severity:** HIGH
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/channels/queue_channel.rb`

**Description:**
The `QueueChannel` streams from a single global channel `"queue_updates"` without any user or session scoping:

```ruby
def subscribed
  stream_from "queue_updates"
end
```

This means all connected users receive the same queue updates, including job IDs and internal system status. While `SyncStatusChannel` correctly uses `stream_for session` for per-session isolation, `QueueChannel` does not.

Additionally, the queue controller broadcasts job-specific data including job IDs:

```ruby
def broadcast_job_update(action, job_id)
  ActionCable.server.broadcast("queue_updates", {
    action: "job_#{action}",
    job_id: job_id,
    # ...
  })
end
```

**Recommended Fix:**
Add authentication checks in the channel subscription and scope broadcasts to authorized users only.

---

### S-12: HIGH - EmailAccountsController Has No Authentication

**Severity:** HIGH
**Epic Affected:** All Epics
**File:** `/Users/esoto/development/expense_tracker/app/controllers/email_accounts_controller.rb`

**Description:**
The `EmailAccountsController` provides full CRUD operations on email accounts (including passwords and IMAP credentials) without any authentication. Any unauthenticated user can:

- List all email accounts and their credentials
- Create new email accounts
- Edit existing email accounts (including setting passwords)
- Delete email accounts

This is the highest-risk unauthenticated controller because email account records contain IMAP credentials that could be used to access users' email inboxes.

```ruby
class EmailAccountsController < ApplicationController
  # No include Authentication
  # No before_action for auth
```

**Recommended Fix:**
```ruby
class EmailAccountsController < ApplicationController
  include Authentication
  before_action :require_admin!
  # ...
end
```

---

### S-13: HIGH - `html_safe` Used with Potentially User-Influenced Data

**Severity:** HIGH
**Epic Affected:** Epic 3
**Files:**
- `/Users/esoto/development/expense_tracker/app/helpers/analytics_helper.rb` (lines 141, 149, 151)
- `/Users/esoto/development/expense_tracker/app/helpers/accessibility_helper.rb` (lines 64, 96, 135, 148, 178)

**Description:**
Multiple helpers use `.html_safe` on joined arrays of `content_tag` outputs. While the immediate use appears to involve `content_tag` (which does escape content), the pattern is fragile. If any of the data passed to these `content_tag` calls contains user-controlled input that is not properly escaped, XSS is possible.

The `announce_to_screen_reader` method in `accessibility_helper.rb` is more concerning as it uses `raw` with a message parameter:

```ruby
def announce_to_screen_reader(message, level = :polite)
  content_tag :script, type: "text/javascript" do
    raw "
      (function() {
        const region = document.getElementById('#{target_id}');
        if (region) {
          region.textContent = '#{j(message)}';  # j() escapes for JS, but...
        }
      })();
    "
  end
end
```

While `j()` (alias for `escape_javascript`) escapes many characters, generating inline `<script>` tags with dynamic content is a high-risk pattern. If the `message` parameter contains carefully crafted input, it could break out of the JS string context.

**Recommended Fix:**
Use data attributes and unobtrusive JavaScript instead of inline scripts:
```ruby
def announce_to_screen_reader(message, level = :polite)
  content_tag :div, "", data: { announce: message, level: level },
              class: "sr-only", aria: { live: level }
end
```

---

### S-14: HIGH - PatternManagementController Permission Check Always Returns True

**Severity:** HIGH
**Epic Affected:** Categorization
**File:** `/Users/esoto/development/expense_tracker/app/controllers/admin/pattern_management_controller.rb`
**Line:** 63-66

**Description:**
The `require_pattern_management_permission` method is overridden as a no-op that always returns `true`:

```ruby
def require_pattern_management_permission
  # Pattern management permission check
  true
end
```

This bypasses the proper role-based permission check defined in the `AdminAuthentication` concern, allowing any authenticated admin user (including `read_only` users) to import patterns, toggle pattern activation, and perform management operations.

**Recommended Fix:**
Remove the override so the method from `AdminAuthentication` concern is used instead:
```ruby
# Remove lines 62-66 entirely. The concern's method will be used automatically.
```

---

### S-15: MEDIUM - Content Security Policy Commented Out Globally

**Severity:** MEDIUM
**Epic Affected:** All Epics
**File:** `/Users/esoto/development/expense_tracker/config/initializers/content_security_policy.rb`

**Description:**
The entire Rails-level Content Security Policy configuration is commented out. While the `AdminAuthentication` concern sets CSP headers manually for admin pages, non-admin pages have no CSP protection at all. This means XSS attacks have no browser-level mitigation.

**Recommended Fix:**
Uncomment and configure the Rails CSP initializer to provide application-wide protection:
```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline  # If needed for Tailwind
    policy.img_src     :self, :data
    policy.connect_src :self
    policy.frame_ancestors :none
  end
end
```

---

### S-16: MEDIUM - Rack::Attack Only Enabled in Production/Staging

**Severity:** MEDIUM
**Epic Affected:** All Epics
**File:** `/Users/esoto/development/expense_tracker/config/initializers/rack_attack.rb`
**Line:** 7 and 275

**Description:**
Two separate mechanisms prevent Rack::Attack from running in non-production environments:
1. Line 7: `return if Rails.env.test?` -- skips all configuration in test
2. Line 275: `if Rails.env.production? || Rails.env.staging?` -- only inserts middleware in production

While skipping in test is reasonable, skipping in development means developers cannot test rate limiting behavior locally. More importantly, if the application is deployed with `RAILS_ENV=development` (as noted in the known issue S-05), all rate limiting is disabled.

**Recommended Fix:**
Enable Rack::Attack in all environments but with relaxed limits in development:
```ruby
Rails.application.config.middleware.use Rack::Attack
```

---

### S-17: MEDIUM - SyncConflictsController Has No Authentication

**Severity:** MEDIUM
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/controllers/sync_conflicts_controller.rb`

**Description:**
The `SyncConflictsController` has no authentication. Any unauthenticated user can:
- List all sync conflicts
- View conflict details including expense data
- Resolve conflicts (modifying expense data)
- Undo conflict resolutions
- Perform bulk conflict resolution
- Preview merge operations

**Recommended Fix:**
```ruby
class SyncConflictsController < ApplicationController
  include Authentication
```

---

### S-18: MEDIUM - SyncPerformanceController Has No Authentication

**Severity:** MEDIUM
**Epic Affected:** Epic 1
**File:** `/Users/esoto/development/expense_tracker/app/controllers/sync_performance_controller.rb`

**Description:**
The `SyncPerformanceController` exposes detailed system performance metrics, email account information, and error messages without authentication. The `export` action allows downloading CSV files containing sync session data.

**Recommended Fix:**
```ruby
class SyncPerformanceController < ApplicationController
  include Authentication
```

---

### S-19: MEDIUM - CategoriesController (Non-API) Has No Authentication

**Severity:** MEDIUM
**Epic Affected:** Epic 3
**File:** `/Users/esoto/development/expense_tracker/app/controllers/categories_controller.rb`

**Description:**
The non-API `CategoriesController` at the root level has no authentication, exposing all category data.

**Recommended Fix:**
```ruby
class CategoriesController < ApplicationController
  include Authentication
```

---

### S-20: MEDIUM - BudgetsController Has No User-Scoped Authentication

**Severity:** MEDIUM
**Epic Affected:** Epic 3
**File:** `/Users/esoto/development/expense_tracker/app/controllers/budgets_controller.rb`

**Description:**
The `BudgetsController` has no authentication requirement and uses `EmailAccount.active.first` to scope data, meaning anyone can access and modify budgets for the first active email account.

**Recommended Fix:**
```ruby
class BudgetsController < ApplicationController
  include Authentication
```

---

### S-21: MEDIUM - UndoHistoriesController Has No Authentication

**Severity:** MEDIUM
**Epic Affected:** Epic 3
**File:** `/Users/esoto/development/expense_tracker/app/controllers/undo_histories_controller.rb`

**Description:**
The undo controller allows any unauthenticated user to undo operations by guessing or discovering undo history IDs.

**Recommended Fix:**
```ruby
class UndoHistoriesController < ApplicationController
  include Authentication
```

---

### S-22: MEDIUM - API Health Endpoint Exposes Internal System Metrics

**Severity:** MEDIUM
**Epic Affected:** Epic 2
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/health_controller.rb`

**Description:**
The health check endpoints expose detailed internal information without authentication:
- Database connection pool stats (size, busy, idle connections)
- Memory usage (RSS, percent)
- Cache statistics (entries, hit rates, memory)
- Total expense counts and categorization statistics
- Pattern counts and activity metrics
- Recent activity timestamps

While `/api/health/live` and `/api/health/ready` should be public for load balancers, the `/api/health/metrics` endpoint leaks too much internal data.

**Recommended Fix:**
Add API token authentication to the metrics endpoint while keeping liveness/readiness probes public:
```ruby
before_action :authenticate_api_token, only: [:index, :metrics]
```

---

### S-23: MEDIUM - Admin Audit Logging Uses `to_unsafe_h`

**Severity:** MEDIUM
**Epic Affected:** Admin
**File:** `/Users/esoto/development/expense_tracker/app/controllers/admin/base_controller.rb`
**Line:** 35

**Description:**
The `filtered_params` method converts parameters to an unsafe hash:

```ruby
def filtered_params
  params.except(:password, :password_confirmation, :authenticity_token).to_unsafe_h
end
```

`to_unsafe_h` bypasses strong parameter filtering and could log sensitive data that was not in the explicit exclusion list (e.g., API keys, tokens, file contents).

**Recommended Fix:**
Use `to_h` on permitted parameters or explicitly whitelist logged params:
```ruby
def filtered_params
  params.permit(:id, :action, :controller).to_h
end
```

---

### S-24: MEDIUM - `announce_to_screen_reader` Uses `raw` With Dynamic Content

**Severity:** MEDIUM
**Epic Affected:** Epic 3
**File:** `/Users/esoto/development/expense_tracker/app/helpers/accessibility_helper.rb`
**Line:** 73

**Description:**
The `announce_to_screen_reader` helper generates inline JavaScript using `raw`:

```ruby
content_tag :script, type: "text/javascript" do
  raw "
    (function() {
      const region = document.getElementById('#{target_id}');
      if (region) {
        region.textContent = '#{j(message)}';
```

While `j()` provides basic JavaScript escaping, this pattern of generating inline scripts is inherently risky. The `target_id` is not escaped at all (though it is derived from the `level` parameter which is a known value).

**Recommended Fix:**
Use data attributes instead of inline scripts.

---

### S-25: LOW - `current_user_email_accounts` Returns All Accounts

**Severity:** LOW
**Epic Affected:** Epic 3
**File:** `/Users/esoto/development/expense_tracker/app/controllers/expenses_controller.rb`
**Line:** 568-572

**Description:**
The method that should scope expenses to the current user actually returns ALL email accounts:

```ruby
def current_user_email_accounts
  # Admin users see all email accounts (no User model for per-user scoping yet).
  @current_user_email_accounts ||= EmailAccount.all
end
```

This means every authenticated user can see and modify all expenses across all email accounts. The comment acknowledges this is intentional for now, but it represents a data isolation gap.

**Recommended Fix:**
When user-level accounts are implemented, scope to `current_user.email_accounts`.

---

### S-26: LOW - Monitoring Health Endpoint Has No Authentication

**Severity:** LOW
**Epic Affected:** Epic 2
**File:** `/Users/esoto/development/expense_tracker/app/controllers/api/monitoring_controller.rb`
**Line:** 23

**Description:**
The `health` and `strategy` actions in the monitoring controller do not require authentication (only `metrics` does). While the `health` endpoint returns minimal data, the `strategy` endpoint reveals the current monitoring strategy and available strategies.

---

### S-27: LOW - ApiToken Authentication Result Cached in Rails.cache

**Severity:** LOW
**Epic Affected:** API
**File:** `/Users/esoto/development/expense_tracker/app/models/api_token.rb`
**Line:** 43

**Description:**
Successful API token authentications are cached for 1 minute:

```ruby
Rails.cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
  # Authentication logic
end
```

If a token is revoked or deactivated, it will continue to work for up to 1 minute until the cache expires. This is a tradeoff between performance and security.

**Recommended Fix:**
Clear the cache entry when a token is deactivated:
```ruby
after_save :clear_auth_cache, if: :saved_change_to_active?

def clear_auth_cache
  # Clear cached authentication for this token
end
```

---

### S-28: LOW - Rate Limiting Test Environment Bypass

**Severity:** LOW
**Epic Affected:** All Epics
**File:** `/Users/esoto/development/expense_tracker/config/initializers/rack_attack.rb`
**Line:** 7

**Description:**
The entire Rack::Attack configuration is skipped in the test environment:
```ruby
return if Rails.env.test?
```

This means rate limiting behavior cannot be tested in the test suite, potentially allowing regressions to go undetected.

---

## Cross-Cutting Concerns

### CSRF Protection Architecture

The application has an inconsistent CSRF protection approach:
- `ApplicationController`: Uses `protect_from_forgery with: :null_session` for JSON requests (correct for APIs)
- `AdminAuthentication` concern: Uses `protect_from_forgery with: :exception` (correct for admin)
- `Admin::SessionsController`: **Skips** CSRF for login (VULNERABLE - S-03)
- All API controllers: Skip CSRF (appropriate for token-authenticated APIs)

### Authentication Architecture

There are three authentication mechanisms, but they are not consistently applied:
1. **`Authentication` concern** (session-based) -- only used by 3 controllers
2. **`AdminAuthentication` concern** -- used by admin controllers via `Admin::BaseController`
3. **API token authentication** -- used by `Api::BaseController` and `Api::WebhooksController`

Many controllers fall through the gaps and have no authentication at all.

### Data Isolation

The application lacks a proper multi-user data isolation model. The `current_user_email_accounts` method returns all accounts, and many controllers do not scope data to the current user. This is acknowledged in code comments but remains a security gap.

---

## Reference: Known Issues

The following 5 issues were already documented in `docs/issues/`:

1. **Authentication Security Gap** (`authentication-security-gap.md`) - Queue controller dev bypass (S-05)
2. **Rate Limiting Configuration Mismatch** (`rate-limiting-configuration-mismatch.md`) - Queue status rate limits too low
3. **WebSocket Connection Recovery Missing** (`websocket-connection-recovery-missing.md`) - No auto-reconnection
4. **Accessibility Compliance Violations** (`accessibility-compliance-violations.md`) - Missing ARIA attributes
5. **JavaScript Error Boundary Missing** (`javascript-error-boundary-missing.md`) - Silent JS failures

---

## Priority Remediation Plan

### Immediate (P0 - Before any deployment)
1. **S-01**: Add authentication to all unprotected controllers
2. **S-02**: Implement real authorization logic in SyncAuthorization
3. **S-03**: Remove CSRF skip on admin login
4. **S-04**: Fix CategoriesController inheritance to use BaseController
5. **S-12**: Protect EmailAccountsController (highest risk due to credential exposure)

### High Priority (P1 - Within 1 sprint)
6. **S-06**: Use `secure_compare` for admin key comparison
7. **S-07**: Require Sidekiq credentials in production
8. **S-08**: Fix MonitoringController authentication method
9. **S-09**: Add authentication/rate limiting to client errors endpoint
10. **S-10**: Remove WebSocket session ID fallback generation
11. **S-11**: Add user scoping to QueueChannel
12. **S-13**: Audit and fix `html_safe` usage
13. **S-14**: Remove permission check override in PatternManagementController

### Medium Priority (P2 - Within 2 sprints)
14. **S-15**: Enable Content Security Policy
15. **S-17-S-21**: Remaining controller authentication gaps
16. **S-22**: Restrict health metrics endpoint
17. **S-23**: Fix unsafe parameter logging
18. **S-24**: Replace inline script generation

### Low Priority (P3 - Backlog)
19. **S-25**: Implement proper user-scoped data isolation
20. **S-26-S-28**: Minor improvements

---

## Appendix: Files Reviewed

### Controllers (37 files)
All files under `app/controllers/` were reviewed, including:
- `application_controller.rb`
- `concerns/authentication.rb`, `admin_authentication.rb`, `sync_authorization.rb`, `sync_error_handling.rb`, `api_configuration.rb`, `api_caching.rb`, `bulk_operation_monitoring.rb`, `rate_limiting.rb`
- `admin/base_controller.rb`, `sessions_controller.rb`, `patterns_controller.rb`, `pattern_management_controller.rb`, `pattern_testing_controller.rb`, `composite_patterns_controller.rb`
- `api/base_controller.rb`, `webhooks_controller.rb`, `queue_controller.rb`, `health_controller.rb`, `monitoring_controller.rb`, `sync_sessions_controller.rb`, `client_errors_controller.rb`
- `api/v1/base_controller.rb`, `categories_controller.rb`, `patterns_controller.rb`, `categorization_controller.rb`
- `expenses_controller.rb`, `categories_controller.rb`, `email_accounts_controller.rb`, `budgets_controller.rb`
- `sync_sessions_controller.rb`, `sync_conflicts_controller.rb`, `sync_performance_controller.rb`
- `bulk_categorizations_controller.rb`, `bulk_categorization_actions_controller.rb`
- `undo_histories_controller.rb`, `ux_mockups_controller.rb`
- `analytics/pattern_dashboard_controller.rb`

### Channels (4 files)
- `application_cable/connection.rb`
- `application_cable/channel.rb`
- `queue_channel.rb`
- `sync_status_channel.rb`

### Models (29 files)
Key models reviewed: `api_token.rb`, `admin_user.rb`, `email_account.rb`, `expense.rb`, `category.rb`, `concerns/query_security.rb`, `concerns/expense_query_optimizer.rb`

### Services (70+ files)
Key services reviewed: `expense_filter_service.rb`, `dashboard_expense_filter_service.rb`, `patterns/csv_importer.rb`, bulk operations services

### Configuration
- `config/routes.rb`
- `config/initializers/rack_attack.rb`
- `config/initializers/content_security_policy.rb`
- `config/initializers/filter_parameter_logging.rb`

### Known Issues (5 files)
All files under `docs/issues/` were reviewed.
