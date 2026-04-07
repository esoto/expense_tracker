# Email Fetching — Urgent Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 7 urgent issues in the email sync pipeline: dead WebSocket detection, XSS via innerHTML, session stuck bug, infinite retry loop, progress callback arity, race condition, and IMAP connection-per-call.

**Architecture:** Tasks are ordered by independence and quick-win potential. Tasks 1-4 are small isolated fixes (5-15 min each, no dependencies). Tasks 5-6 are medium (30 min each, touch related code). Task 7 is the largest refactor (IMAP connection pooling). All follow TDD.

**Tech Stack:** Rails 8.1.2, Stimulus/JS, ActionCable, PostgreSQL, RSpec, Net::IMAP

---

### Task 1: Fix isWebSocketSupported() dead endpoint (PER-345)

**Files:**
- Modify: `app/javascript/controllers/sync_widget_controller.js:1126-1145`

**Step 1: Replace the dead WebSocket test**

In `sync_widget_controller.js`, find the `isWebSocketSupported()` method (~line 1126) and replace the entire try/catch body:

```javascript
isWebSocketSupported() {
  try {
    return 'WebSocket' in window && window.WebSocket !== undefined
  } catch (error) {
    return false
  }
}
```

This removes the network request to `wss://echo.websocket.org/` (dead endpoint) and uses simple feature detection. The existing `handleDisconnected` + `scheduleReconnect` already handle actual WebSocket failures gracefully with polling fallback.

**Step 2: Verify manually**

Run: `bin/rails server` and open the sync page in browser DevTools Network tab.
Expected: No request to `echo.websocket.org`. ActionCable WebSocket connection attempted to your server.

**Step 3: Commit**

```bash
git add app/javascript/controllers/sync_widget_controller.js
git commit -m "fix(sync): replace dead WebSocket detection endpoint with feature detection (PER-345)

isWebSocketSupported() was testing against wss://echo.websocket.org/ which shut
down years ago, forcing ALL users into polling mode. Now uses 'WebSocket' in window."
```

---

### Task 2: Fix SyncSessionAccount infinite retry loop (PER-343)

**Files:**
- Modify: `app/models/sync_session_account.rb:49-64`
- Test: `spec/models/sync_session_account_spec.rb`

**Step 1: Write the failing test**

Add to `spec/models/sync_session_account_spec.rb`:

```ruby
describe "#update_progress" do
  let(:sync_session) { create(:sync_session, :running) }
  let(:account) { create(:sync_session_account, sync_session: sync_session, status: "processing") }

  it "retries up to 3 times on StaleObjectError then stops gracefully" do
    call_count = 0
    allow(sync_session).to receive(:update_progress) do
      call_count += 1
      raise ActiveRecord::StaleObjectError.new(sync_session, "update")
    end
    allow(account).to receive(:sync_session).and_return(sync_session)

    expect { account.update_progress(5, 10, 1) }.not_to raise_error
    expect(call_count).to eq(4) # initial + 3 retries
  end

  it "succeeds on retry after StaleObjectError" do
    call_count = 0
    allow(sync_session).to receive(:update_progress) do
      call_count += 1
      raise ActiveRecord::StaleObjectError.new(sync_session, "update") if call_count == 1
    end
    allow(account).to receive(:sync_session).and_return(sync_session)

    expect { account.update_progress(5, 10, 1) }.not_to raise_error
    expect(call_count).to eq(2)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb -e "retries up to 3 times" --tag ~unit`
Expected: FAIL — infinite loop or SystemStackError

**Step 3: Implement the fix**

In `app/models/sync_session_account.rb`, replace lines 49-64:

```ruby
def update_progress(processed, total, detected = 0)
  retries = 0
  begin
    # Use update_columns to avoid callbacks and optimistic locking for progress updates
    update_columns(
      processed_emails: processed,
      total_emails: total,
      detected_expenses: detected_expenses + detected,
      updated_at: Time.current
    )

    # Update parent session progress
    sync_session.update_progress
  rescue ActiveRecord::StaleObjectError
    retries += 1
    if retries <= 3
      reload
      retry
    else
      Rails.logger.warn "[SyncSessionAccount] Max retries (3) for update_progress on account #{id}"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb -e "retries up to 3 times|succeeds on retry" --tag ~unit`
Expected: PASS

**Step 5: Run full model specs**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/models/sync_session_account.rb spec/models/sync_session_account_spec.rb
git commit -m "fix(sync): add max retry limit to SyncSessionAccount#update_progress (PER-343)

Previously had no retry counter on StaleObjectError rescue, could loop
indefinitely. Now retries up to 3 times then logs warning and continues."
```

---

### Task 3: Fix SyncSession stuck in running — event-driven completion (PER-339)

**Files:**
- Modify: `app/models/sync_session_account.rb`
- Modify: `app/jobs/sync_session_monitor_job.rb`
- Test: `spec/models/sync_session_account_spec.rb`
- Test: `spec/jobs/sync_session_monitor_job_spec.rb` (if exists, else create)

**Step 1: Write the failing test for event-driven completion**

Add to `spec/models/sync_session_account_spec.rb`:

```ruby
describe "#check_session_completion" do
  let(:sync_session) { create(:sync_session, :running) }
  let!(:account_1) { create(:sync_session_account, sync_session: sync_session, status: "processing") }
  let!(:account_2) { create(:sync_session_account, sync_session: sync_session, status: "processing") }

  it "completes session when all accounts are done with mixed results" do
    account_1.complete!
    account_2.fail!("Auth error")

    sync_session.reload
    expect(sync_session.status).to eq("completed")
  end

  it "fails session when ALL accounts failed" do
    account_1.fail!("Auth error 1")
    account_2.fail!("Auth error 2")

    sync_session.reload
    expect(sync_session.status).to eq("failed")
    expect(sync_session.error_details).to include("Auth error 1")
    expect(sync_session.error_details).to include("Auth error 2")
  end

  it "does not complete session while accounts are still processing" do
    account_1.complete!
    # account_2 still processing

    sync_session.reload
    expect(sync_session.status).to eq("running")
  end

  it "does not trigger on non-running sessions" do
    sync_session.update!(status: "completed")
    account_1.update!(status: "completed")
    # Should not raise or change anything
    expect(sync_session.reload.status).to eq("completed")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb -e "check_session_completion" --tag ~unit`
Expected: FAIL — session stays "running"

**Step 3: Implement event-driven completion**

In `app/models/sync_session_account.rb`, add the callback and method after the existing `fail!` method:

```ruby
after_update :check_session_completion, if: -> { saved_change_to_status? && (completed? || failed?) }

private

def check_session_completion
  return unless sync_session.running?

  pending_siblings = sync_session.sync_session_accounts.where(status: %w[pending waiting processing])
  return if pending_siblings.exists?

  all_failed = sync_session.sync_session_accounts.where.not(status: "failed").none?

  if all_failed
    error_messages = sync_session.sync_session_accounts
      .where.not(last_error: nil)
      .pluck(:last_error)
      .join("; ")
    sync_session.fail!(error_messages.presence || "All accounts failed")
  else
    sync_session.complete!
  end
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error "[SyncSessionAccount] Failed to auto-complete session #{sync_session.id}: #{e.message}"
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb -e "check_session_completion" --tag ~unit`
Expected: PASS

**Step 5: Add monitor job deadline**

In `app/jobs/sync_session_monitor_job.rb`, add timeout check after line 12 (`return unless sync_session.running?`):

```ruby
# Timeout: force-fail sessions running longer than 30 minutes
if sync_session.started_at && sync_session.started_at < 30.minutes.ago
  sync_session.fail!("Sync timed out after 30 minutes")
  Rails.logger.warn "Sync session #{sync_session_id} force-failed: exceeded 30-minute timeout"
  return
end
```

**Step 6: Run all related specs**

Run: `bundle exec rspec spec/models/sync_session_account_spec.rb spec/jobs/sync_session_monitor_job_spec.rb spec/models/sync_session_spec.rb`
Expected: All pass

**Step 7: Commit**

```bash
git add app/models/sync_session_account.rb app/jobs/sync_session_monitor_job.rb spec/
git commit -m "fix(sync): add event-driven session completion + 30-min monitor timeout (PER-339)

SyncSessionAccount now triggers session completion check via after_update
callback when reaching completed/failed state. This makes completion
event-driven rather than relying solely on the polling monitor job.

Also adds 30-minute deadline to SyncSessionMonitorJob to prevent
sessions from being stuck in running state indefinitely."
```

---

### Task 4: Fix queue mismatch (PER-348) + delete dead code (PER-362)

**Files:**
- Modify: `app/jobs/process_email_job.rb:2`
- Modify: `app/jobs/sync_session_monitor_job.rb:2`
- Modify: `app/jobs/process_emails_job.rb:152-161`

**Step 1: Fix queue assignments**

In `app/jobs/process_email_job.rb`, change line 2:
```ruby
queue_as :email_processing
```

In `app/jobs/sync_session_monitor_job.rb`, change line 2:
```ruby
queue_as :email_processing
```

**Step 2: Delete dead code**

In `app/jobs/process_emails_job.rb`, delete the entire `process_all_accounts_in_batches` method (lines 152-161).

**Step 3: Run job specs**

Run: `bundle exec rspec spec/jobs/process_email_job_spec.rb spec/jobs/process_emails_job_spec.rb`
Expected: All pass

**Step 4: Commit**

```bash
git add app/jobs/process_email_job.rb app/jobs/sync_session_monitor_job.rb app/jobs/process_emails_job.rb
git commit -m "fix(jobs): align all email sync jobs to :email_processing queue + delete dead code (PER-348, PER-362)

ProcessEmailJob and SyncSessionMonitorJob were on :default queue while
ProcessEmailsJob was on :email_processing. Also removes unused
process_all_accounts_in_batches method which contained a sleep(1)."
```

---

### Task 5: Fix SyncSession.active.last race condition (PER-342)

**Files:**
- Modify: `app/jobs/process_email_job.rb:6,17-19`
- Modify: `app/services/email_processing/processor.rb:6-8,83,266-301`
- Test: `spec/jobs/process_email_job_spec.rb`
- Test: `spec/services/email_processing/processor_spec.rb`

**Step 1: Write the failing test**

Add to `spec/jobs/process_email_job_spec.rb`:

```ruby
describe "sync session threading" do
  let(:email_account) { create(:email_account) }
  let(:sync_session) { create(:sync_session, :running) }
  let(:email_data) { { subject: "Test", body: "Test body", date: Time.current } }

  it "uses explicitly passed sync_session_id instead of global lookup" do
    other_session = create(:sync_session, :running) # newer session

    expect(Services::SyncMetricsCollector).to receive(:new).with(sync_session).and_call_original

    ProcessEmailJob.perform_now(email_account.id, email_data, sync_session.id)
  end

  it "works without sync_session_id for backwards compatibility" do
    expect { ProcessEmailJob.perform_now(email_account.id, email_data) }.not_to raise_error
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/process_email_job_spec.rb -e "sync session threading" --tag ~unit`
Expected: FAIL — still uses `SyncSession.active.last`

**Step 3: Update ProcessEmailJob to accept sync_session_id**

In `app/jobs/process_email_job.rb`, change the `perform` method signature and lookup:

```ruby
def perform(email_account_id, email_data, sync_session_id = nil)
  email_account = EmailAccount.find_by(id: email_account_id)

  unless email_account
    Rails.logger.error "EmailAccount not found: #{email_account_id}"
    return
  end

  Rails.logger.info "Processing individual email for: #{email_account.email}"
  Rails.logger.debug "Email data: #{email_data.inspect}"

  # Use explicit sync session ID instead of global lookup
  sync_session = sync_session_id ? SyncSession.find_by(id: sync_session_id) : nil
  metrics_collector = Services::SyncMetricsCollector.new(sync_session) if sync_session
```

**Step 4: Update Processor to thread sync_session through**

In `app/services/email_processing/processor.rb`:

a) Change constructor to accept `sync_session`:
```ruby
def initialize(email_account, metrics_collector: nil, sync_session: nil)
  @email_account = email_account
  @metrics_collector = metrics_collector
  @sync_session = sync_session
  @errors = []
end
```

b) In `process_email_with_metrics`, where it enqueues `ProcessEmailJob` (~line 83), pass the sync_session_id:
```ruby
ProcessEmailJob.perform_later(email_account.id, email_data, @sync_session&.id)
```

c) In `detect_and_handle_conflict` (~line 287), replace `SyncSession.active.last` with `@sync_session`:
```ruby
if @sync_session
  detector = Services::ConflictDetectionService.new(@sync_session, metrics_collector: @metrics_collector)
  conflict = detector.detect_conflict_for_expense(expense_data)
  return true if conflict
end
```

**Step 5: Update Fetcher to pass sync_session to Processor**

In `app/services/email_processing/fetcher.rb`, update the Processor initialization (~line 8):
```ruby
@email_processor = email_processor || Processor.new(
  email_account,
  metrics_collector: metrics_collector,
  sync_session: sync_session_account&.sync_session
)
```

**Step 6: Run tests**

Run: `bundle exec rspec spec/jobs/process_email_job_spec.rb spec/services/email_processing/processor_spec.rb spec/services/email_processing/fetcher_spec.rb`
Expected: All pass (some existing specs may need sync_session mocking updates)

**Step 7: Grep for remaining `SyncSession.active.last`**

Run: `grep -rn "SyncSession.active.last" app/`
Expected: Zero results (only test files may have it)

**Step 8: Commit**

```bash
git add app/jobs/process_email_job.rb app/services/email_processing/processor.rb app/services/email_processing/fetcher.rb spec/
git commit -m "fix(sync): thread sync_session_id explicitly — eliminate SyncSession.active.last race (PER-342)

ProcessEmailJob now accepts sync_session_id as explicit parameter.
Processor receives sync_session via constructor and passes it to child
jobs and conflict detection. No more global SyncSession.active.last
lookups that could attribute metrics to the wrong session."
```

---

### Task 6: Fix XSS via innerHTML in all 3 sync controllers (PER-344)

**Files:**
- Modify: `app/javascript/controllers/sync_widget_controller.js`
- Modify: `app/javascript/controllers/sync_sessions_controller.js`
- Modify: `app/javascript/controllers/sync_session_detail_controller.js`

**Step 1: Fix sync_sessions_controller.js (2 innerHTML uses)**

Replace `countsElement.innerHTML` (~line 169) with:
```javascript
if (countsElement) {
  countsElement.textContent = ''
  const processed = document.createElement('span')
  processed.textContent = `${data.processed || 0} / ${data.total || 0}`
  const detected = document.createElement('span')
  detected.textContent = `${data.detected || 0} gastos`
  countsElement.appendChild(processed)
  countsElement.appendChild(detected)
}
```

Replace `notification.innerHTML` in `showNotification` (~line 230) with:
```javascript
const flexDiv = document.createElement('div')
flexDiv.className = 'flex items-center'
const messageSpan = document.createElement('span')
messageSpan.textContent = message
const closeBtn = document.createElement('button')
closeBtn.className = 'ml-4 text-current opacity-70 hover:opacity-100'
closeBtn.addEventListener('click', () => notification.remove())
const closeSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
closeSvg.setAttribute('class', 'w-4 h-4')
closeSvg.setAttribute('fill', 'none')
closeSvg.setAttribute('stroke', 'currentColor')
closeSvg.setAttribute('viewBox', '0 0 24 24')
const closePath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
closePath.setAttribute('stroke-linecap', 'round')
closePath.setAttribute('stroke-linejoin', 'round')
closePath.setAttribute('stroke-width', '2')
closePath.setAttribute('d', 'M6 18L18 6M6 6l12 12')
closeSvg.appendChild(closePath)
closeBtn.appendChild(closeSvg)
flexDiv.appendChild(messageSpan)
flexDiv.appendChild(closeBtn)
notification.appendChild(flexDiv)
```

**Step 2: Fix sync_session_detail_controller.js (4 innerHTML uses)**

Apply same pattern: replace `processedText.innerHTML` (~line 165), `detectedText.innerHTML` (~line 175), `statusBadge.innerHTML` (~line 205) with `textContent`, and `notification.innerHTML` in `showNotification` (~line 230) with the same createElement pattern as Step 1.

For `processedText` and `detectedText`:
```javascript
if (processedText) {
  processedText.textContent = `${data.processed_emails || 0} / ${data.total_emails || 0}`
}
if (detectedText) {
  detectedText.textContent = `${data.detected_expenses || 0}`
}
```

For `statusBadge`:
```javascript
if (statusBadge) {
  statusBadge.className = 'px-3 py-1 rounded-full text-sm font-medium inline-flex items-center bg-emerald-100 text-emerald-800'
  statusBadge.textContent = 'Completado'
}
```

**Step 3: Fix sync_widget_controller.js (10 innerHTML uses)**

a) `updateStatusIcon` (~lines 698-729): Replace SVG innerHTML with createElement:
```javascript
updateStatusIcon(element, status) {
  element.textContent = ''

  const svgNS = 'http://www.w3.org/2000/svg'
  const createSvg = (cls, paths) => {
    const svg = document.createElementNS(svgNS, 'svg')
    svg.setAttribute('aria-hidden', 'true')
    svg.setAttribute('class', cls)
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('viewBox', '0 0 24 24')
    paths.forEach(d => {
      const path = document.createElementNS(svgNS, 'path')
      path.setAttribute('stroke-linecap', 'round')
      path.setAttribute('stroke-linejoin', 'round')
      path.setAttribute('stroke-width', '2')
      path.setAttribute('d', d)
      svg.appendChild(path)
    })
    return svg
  }

  switch(status) {
    case 'processing':
    case 'running': {
      const svg = document.createElementNS(svgNS, 'svg')
      svg.setAttribute('aria-hidden', 'true')
      svg.setAttribute('class', 'animate-spin h-4 w-4 text-teal-700')
      svg.setAttribute('fill', 'none')
      svg.setAttribute('viewBox', '0 0 24 24')
      const circle = document.createElementNS(svgNS, 'circle')
      circle.setAttribute('class', 'opacity-25')
      circle.setAttribute('cx', '12')
      circle.setAttribute('cy', '12')
      circle.setAttribute('r', '10')
      circle.setAttribute('stroke', 'currentColor')
      circle.setAttribute('stroke-width', '4')
      const path = document.createElementNS(svgNS, 'path')
      path.setAttribute('class', 'opacity-75')
      path.setAttribute('fill', 'currentColor')
      path.setAttribute('d', 'M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z')
      svg.appendChild(circle)
      svg.appendChild(path)
      element.appendChild(svg)
      break
    }
    case 'completed':
      element.appendChild(createSvg('h-4 w-4 text-emerald-600', ['M5 13l4 4L19 7']))
      break
    case 'failed':
      element.appendChild(createSvg('h-4 w-4 text-rose-600', ['M6 18L18 6M6 6l12 12']))
      break
    default: {
      const dot = document.createElement('div')
      dot.className = 'h-4 w-4 rounded-full bg-slate-300'
      element.appendChild(dot)
    }
  }
}
```

b) `pauseSync` and `resumeSync` button innerHTML (~lines 790, 803, 828, 840): Replace with `textContent` for the text and createElement for the SVG. Since these are button labels with icons, use the same createSvg pattern and append + textContent.

c) `showPollingIndicator` (~line 1251): Same createElement pattern.

**Step 4: Grep for remaining innerHTML**

Run: `grep -n "innerHTML" app/javascript/controllers/sync_widget_controller.js app/javascript/controllers/sync_sessions_controller.js app/javascript/controllers/sync_session_detail_controller.js`
Expected: Zero results

**Step 5: Verify manually**

Run the dev server and test: sync center, session detail, widget. Check all status icons, pause/resume button, notifications render correctly.

**Step 6: Commit**

```bash
git add app/javascript/controllers/
git commit -m "security(sync): replace all innerHTML with createElement/textContent — XSS fix (PER-344)

Eliminates 16 innerHTML uses across 3 sync Stimulus controllers that
embedded server-provided error strings directly into HTML. Uses
createElement + textContent for safe DOM manipulation."
```

---

### Task 7: Fix progress callback arity mismatch (PER-341)

**Files:**
- Modify: `app/services/email_processing/processor.rb:18-28,60-93`
- Test: `spec/services/email_processing/processor_spec.rb`

**Step 1: Write the failing test**

Add to `spec/services/email_processing/processor_spec.rb`:

```ruby
describe "#process_emails progress callback" do
  let(:email_account) { create(:email_account, :bac) }
  let(:processor) { described_class.new(email_account) }
  let(:imap_service) { instance_double(Services::ImapConnectionService) }

  it "passes expense data as third argument to progress callback" do
    envelope = double("envelope", subject: "Notificación de transacción", from: nil, date: Time.current)
    allow(imap_service).to receive(:fetch_envelope).and_return(envelope)
    allow(imap_service).to receive(:fetch_body_structure).and_return(nil)
    allow(imap_service).to receive(:fetch_text_body).and_return("Monto: 5000 Fecha: Apr 5, 2026, 10:00 Comercio: TestMerchant")
    allow(ProcessEmailJob).to receive(:perform_later)

    callback_args = []
    processor.process_emails([1], imap_service) do |*args|
      callback_args = args
    end

    expect(callback_args.length).to eq(3)
    expect(callback_args[2]).to be_a(Hash) # expense data
    expect(callback_args[2]).to have_key(:merchant_name)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email_processing/processor_spec.rb -e "passes expense data as third argument" --tag ~unit`
Expected: FAIL — callback only receives 2 args

**Step 3: Implement the fix**

In `app/services/email_processing/processor.rb`:

a) Change `process_emails` to capture and pass expense data from the result (~line 18-28):
```ruby
def process_emails(message_ids, imap_service, &progress_callback)
  return { processed_count: 0, total_count: 0, detected_expenses_count: 0 } if message_ids.empty?

  processed_count = 0
  detected_expenses_count = 0
  total_count = message_ids.length

  message_ids.each_with_index do |message_id, index|
    result = process_single_email(message_id, imap_service)
    if result[:processed]
      processed_count += 1
      detected_expenses_count += 1 if result[:expense_created]
    end

    # Call progress callback with expense data as third argument
    if progress_callback
      expense_data = result[:expense_created] ? result[:expense_data] : nil
      progress_callback.call(index + 1, detected_expenses_count, expense_data)
    end
  end

  Rails.logger.info "Processed #{processed_count} transaction emails out of #{total_count} total emails"
  {
    processed_count: processed_count,
    total_count: total_count,
    detected_expenses_count: detected_expenses_count
  }
end
```

b) In `process_email_with_metrics` (~line 60-93), include parsed expense data in the return hash when an expense would be created:
```ruby
# After the line that queues ProcessEmailJob (around line 83):
{
  processed: true,
  expense_created: true,
  expense_data: {
    merchant_name: email_data[:body]&.match(/(?:Comercio|merchant)[\s:]+([^\n\r]+)/i)&.captures&.first&.strip,
    amount: expense_data_from_conflict&.dig(:amount),
    subject: email_data[:subject]
  }
}
```

Note: Since the Processor already pre-parses for conflict detection, capture that parsed data. If conflict detection was skipped, pass basic info from the email_data hash.

**Step 4: Run tests**

Run: `bundle exec rspec spec/services/email_processing/processor_spec.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/email_processing/processor.rb spec/services/email_processing/processor_spec.rb
git commit -m "fix(sync): pass expense data as third arg in progress callback (PER-341)

Processor now passes parsed expense data (merchant, amount, subject) to
the progress callback so Fetcher can broadcast expense_detected events
via SyncStatusChannel. Previously the third arg was always nil due to
arity mismatch."
```

---

## Verification

After all 7 tasks, run the full email processing test suite:

```bash
bundle exec rspec spec/services/email_processing/ spec/jobs/process_email* spec/models/sync_session_spec.rb spec/models/sync_session_account_spec.rb
```

Then run unit tests + rubocop + brakeman to verify pre-commit hook passes:

```bash
bundle exec rspec --tag unit
bundle exec rubocop
bundle exec brakeman -q
```
