# PER-340: IMAP Connection Pooling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Reduce ~87 TCP/TLS handshakes per 29-email sync to ~2 by adding session reuse to ImapConnectionService.

**Architecture:** Add a `with_session` method to `ImapConnectionService` that opens one IMAP connection, stores it in `@active_session`, and yields. All existing public methods (`search_emails`, `fetch_envelope`, `fetch_body_structure`, `fetch_body_part`, `fetch_text_body`) check `@active_session` first — if set, use it directly; if not, fall back to `with_connection` (backward-compatible). `Fetcher#search_and_process_emails` wraps the entire search+process batch in `imap_service.with_session { ... }`, so Processor gets the reused connection transparently.

**Tech Stack:** Ruby, Rails, Net::IMAP (net-imap 0.6.3), RSpec

**Risks:**
- Mid-batch IMAP disconnect (stale connection) — mitigated by reconnect-once logic in `with_session`
- Thread safety — not a concern since each job creates its own `ImapConnectionService` instance
- Ensure cleanup happens even on exceptions (use `ensure` block)

**Out of scope:**
- Connection pooling across jobs (each job gets its own connection)
- Refactoring Email::ProcessingService (PER-361)
- OAuth2 authentication (current service uses password auth only)

---

### Task 1: Add `with_session` to ImapConnectionService

**Files:**
- Modify: `app/services/imap_connection_service.rb`
- Test: `spec/services/imap_connection_service_spec.rb`

**Context:** This is the core change. `with_session` opens one connection, stores it in `@active_session`, yields, then cleans up. All existing public fetch methods are modified to check `@active_session` — if present, use it directly instead of calling `with_connection`.

- [ ] **Step 1: Write failing tests for `with_session`**

  Add to `spec/services/imap_connection_service_spec.rb`:

  ```ruby
  describe '#with_session' do
    let(:mock_imap) { instance_double(Net::IMAP) }

    before do
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)
      allow(mock_imap).to receive(:respond_to?).and_return(true)
    end

    it 'opens exactly one connection for the entire block' do
      service.with_session do
        service.search_emails(["SINCE", "01-Jan-2026"])
        service.fetch_envelope(1)
        service.fetch_body_structure(1)
      end

      expect(Net::IMAP).to have_received(:new).once
    end

    it 'authenticates and selects INBOX once' do
      service.with_session do
        service.fetch_envelope(1)
        service.fetch_envelope(2)
      end

      expect(mock_imap).to have_received(:login).once
      expect(mock_imap).to have_received(:select).with("INBOX").once
    end

    it 'cleans up after the block completes' do
      service.with_session do
        service.fetch_envelope(1)
      end

      expect(mock_imap).to have_received(:logout).once
      expect(mock_imap).to have_received(:disconnect).once
    end

    it 'cleans up even when the block raises' do
      expect {
        service.with_session do
          raise StandardError, "something went wrong"
        end
      }.to raise_error(StandardError, "something went wrong")

      expect(mock_imap).to have_received(:logout)
      expect(mock_imap).to have_received(:disconnect)
    end

    it 'validates account before opening connection' do
      allow(email_account).to receive(:active?).and_return(false)

      expect {
        service.with_session { }
      }.to raise_error(Services::ImapConnectionService::ConnectionError, /not active/)

      expect(Net::IMAP).not_to have_received(:new)
    end

    it 'raises ConnectionError on authentication failure' do
      allow(mock_imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new(double(data: double(text: "auth failed"))))

      expect {
        service.with_session { }
      }.to raise_error(Services::ImapConnectionService::AuthenticationError)
    end
  end
  ```

  Also add a test for backward compatibility — calling fetch methods outside `with_session` still works:

  ```ruby
  describe 'backward compatibility' do
    it 'fetch methods work without with_session (per-call connection)' do
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)
      allow(mock_imap).to receive(:respond_to?).and_return(true)
      allow(mock_imap).to receive(:fetch).and_return([double(attr: { "ENVELOPE" => double })])

      service.fetch_envelope(1)
      service.fetch_envelope(2)

      # Without with_session, each call opens its own connection
      expect(Net::IMAP).to have_received(:new).twice
    end
  end
  ```

- [ ] **Step 2: Run tests to verify they fail**

  Run: `bundle exec rspec spec/services/imap_connection_service_spec.rb --tag unit --fail-fast`
  Expected: FAIL — `with_session` method does not exist

- [ ] **Step 3: Implement `with_session` and modify fetch methods**

  In `app/services/imap_connection_service.rb`:

  ```ruby
  def with_session
    validate_account!

    @active_session = create_connection
    authenticate_connection(@active_session)
    select_inbox(@active_session)

    yield
  ensure
    session = @active_session
    @active_session = nil
    cleanup_connection(session)
  end
  ```

  Then modify each public method to check `@active_session`. Example for `fetch_envelope`:

  ```ruby
  def fetch_envelope(message_id)
    execute_imap_command do |imap|
      result = imap.fetch(message_id, "ENVELOPE")
      result&.first&.attr&.dig("ENVELOPE")
    end
  rescue Net::IMAP::Error => e
    add_error("Failed to fetch envelope for message #{message_id}: #{e.message}")
    nil
  end
  ```

  Add the private helper:

  ```ruby
  def execute_imap_command(&block)
    if @active_session
      yield @active_session
    else
      with_connection(&block)
    end
  end
  ```

  Apply the same `execute_imap_command` pattern to: `search_emails`, `fetch_body_structure`, `fetch_body_part`, `fetch_text_body`, `test_connection`.

- [ ] **Step 4: Run tests to verify they pass**

  Run: `bundle exec rspec spec/services/imap_connection_service_spec.rb --tag unit`
  Expected: PASS — all existing tests pass plus new `with_session` tests

- [ ] **Step 5: Commit**

  ```bash
  git add app/services/imap_connection_service.rb spec/services/imap_connection_service_spec.rb
  git commit -m "feat(imap): add with_session for connection reuse (PER-340)"
  ```

---

### Task 2: Wire `with_session` into Fetcher

**Files:**
- Modify: `app/services/email_processing/fetcher.rb`
- Test: `spec/services/email_processing/fetcher_spec.rb`

**Context:** `Fetcher#search_and_process_emails` currently calls `imap_service.search_emails(criteria)` and then passes `imap_service` to `email_processor.process_emails(message_ids, imap_service)`. Wrap the entire method body in `imap_service.with_session { ... }` so both search and processing share one connection.

- [ ] **Step 1: Write failing test**

  Add to `spec/services/email_processing/fetcher_spec.rb`:

  ```ruby
  describe 'IMAP session reuse' do
    it 'wraps search and processing in a single IMAP session' do
      expect(mock_imap_service).to receive(:with_session).and_yield

      fetcher.fetch_new_emails
    end
  end
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `bundle exec rspec spec/services/email_processing/fetcher_spec.rb --tag unit --fail-fast`
  Expected: FAIL — `with_session` not called

- [ ] **Step 3: Implement**

  In `app/services/email_processing/fetcher.rb`, modify `search_and_process_emails`:

  ```ruby
  def search_and_process_emails(since)
    imap_service.with_session do
      # ... existing method body (search, process, progress tracking) unchanged ...
    end
  end
  ```

  The entire existing method body moves inside the block. No other changes needed — `imap_service.search_emails` and the `imap_service` passed to `process_emails` will transparently use the active session.

- [ ] **Step 4: Update existing test stubs**

  All existing Fetcher specs that stub `mock_imap_service.search_emails` need to also stub `with_session`:

  ```ruby
  # Add to the shared before block or let:
  allow(mock_imap_service).to receive(:with_session).and_yield
  ```

  Apply this to all fetcher spec files:
  - `spec/services/email_processing/fetcher_spec.rb`
  - `spec/services/email_processing/fetcher_error_handling_spec.rb`
  - `spec/services/email_processing/fetcher_progress_spec.rb`
  - `spec/services/email_processing/fetcher_broadcasting_spec.rb`
  - `spec/services/email_processing/fetcher_sync_session_spec.rb`
  - `spec/services/email_processing/fetcher_metrics_spec.rb`

- [ ] **Step 5: Run all fetcher specs to verify they pass**

  Run: `bundle exec rspec spec/services/email_processing/fetcher_spec.rb spec/services/email_processing/fetcher_error_handling_spec.rb spec/services/email_processing/fetcher_progress_spec.rb spec/services/email_processing/fetcher_broadcasting_spec.rb spec/services/email_processing/fetcher_sync_session_spec.rb spec/services/email_processing/fetcher_metrics_spec.rb --tag unit`
  Expected: PASS

- [ ] **Step 6: Commit**

  ```bash
  git add app/services/email_processing/fetcher.rb spec/services/email_processing/fetcher_spec.rb spec/services/email_processing/fetcher_error_handling_spec.rb spec/services/email_processing/fetcher_progress_spec.rb spec/services/email_processing/fetcher_broadcasting_spec.rb spec/services/email_processing/fetcher_sync_session_spec.rb spec/services/email_processing/fetcher_metrics_spec.rb
  git commit -m "feat(fetcher): use with_session for IMAP connection reuse (PER-340)"
  ```

---

### Task 3: Full integration test — connection count assertion

**Files:**
- Create: `spec/services/email_processing/fetcher_connection_reuse_spec.rb`

**Context:** End-to-end test that proves the entire Fetcher → Processor pipeline opens exactly 1 IMAP connection for a multi-email batch. This is the acceptance test for PER-340.

- [ ] **Step 1: Write the integration test**

  ```ruby
  require 'rails_helper'

  RSpec.describe 'IMAP connection reuse', type: :service, unit: true do
    let(:email_account) { create(:email_account, :bac) }
    let(:service) { Services::ImapConnectionService.new(email_account) }
    let(:mock_imap) { instance_double(Net::IMAP) }
    let(:mock_envelope) { double('envelope', subject: 'Notificación de transacción', from: [double(mailbox: 'alerts', host: 'bac.net')], date: Time.current) }

    before do
      allow(Net::IMAP).to receive(:new).and_return(mock_imap)
      allow(mock_imap).to receive(:login)
      allow(mock_imap).to receive(:select)
      allow(mock_imap).to receive(:logout)
      allow(mock_imap).to receive(:disconnect)
      allow(mock_imap).to receive(:respond_to?).and_return(true)
      allow(mock_imap).to receive(:search).and_return([1, 2, 3])
      allow(mock_imap).to receive(:fetch).and_return([double(attr: {
        "ENVELOPE" => mock_envelope,
        "BODYSTRUCTURE" => double(media_type: "TEXT", subtype: "PLAIN", multipart?: false),
        "BODY[TEXT]" => "Monto: 5000 Comercio: Test"
      })])
    end

    it 'opens exactly 1 IMAP connection for 3 emails' do
      fetcher = Services::EmailProcessing::Fetcher.new(email_account, imap_service: service)

      # Stub processor to avoid job enqueuing
      allow_any_instance_of(Services::EmailProcessing::Processor).to receive(:process_emails).and_return(processed_count: 3)

      fetcher.fetch_new_emails(since: 1.week.ago)

      expect(Net::IMAP).to have_received(:new).once
    end
  end
  ```

- [ ] **Step 2: Run test**

  Run: `bundle exec rspec spec/services/email_processing/fetcher_connection_reuse_spec.rb --tag unit`
  Expected: PASS (if Task 1 and 2 are done correctly)

- [ ] **Step 3: Commit**

  ```bash
  git add spec/services/email_processing/fetcher_connection_reuse_spec.rb
  git commit -m "test(imap): add connection reuse integration test (PER-340)"
  ```

---

### Task 4: Run full test suite and fix regressions

**Files:**
- Possibly modify: `spec/support/email_processing_processor_test_helper.rb`
- Possibly modify: various processor spec files

**Context:** The `MockImapService` in test helpers and any processor specs that pass `imap_service` to `process_emails` may need a `with_session` stub. Since Processor doesn't call `with_session` directly (Fetcher does), most Processor specs should pass unchanged. But verify and fix any failures.

- [ ] **Step 1: Run full unit test suite**

  Run: `bundle exec rspec --tag unit --fail-fast=5`
  Expected: PASS — if failures, fix the stubs

- [ ] **Step 2: Fix any failures**

  If `MockImapService` needs updating, add:
  ```ruby
  def with_session
    yield
  end
  ```

- [ ] **Step 3: Run RuboCop and Brakeman**

  Run: `bundle exec rubocop app/services/imap_connection_service.rb app/services/email_processing/fetcher.rb`
  Run: `bundle exec brakeman -q`

- [ ] **Step 4: Final commit if fixes were needed**

  ```bash
  git add -A
  git commit -m "fix(tests): align test helpers with with_session API (PER-340)"
  ```
