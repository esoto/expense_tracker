# frozen_string_literal: true

require "rails_helper"

# Specs for Services::ErrorTrackingService — the centralized error-tracking
# facade wired to Sentry in PER-526.
#
# These tests NEVER send real Sentry events. `Sentry.capture_exception` and
# `Sentry.capture_message` are stubbed so no network calls occur and the gem's
# background worker is not started.
RSpec.describe Services::ErrorTrackingService, type: :service, unit: true do
  subject(:service) { described_class.instance }

  let(:exception) { RuntimeError.new("boom") }
  let(:context)   { { user_id: 42, action: "test_action" } }

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  # Simulate Sentry being initialized (DSN present, non-test call path).
  def with_sentry_active
    allow(Sentry).to receive(:initialized?).and_return(true)
    yield
  end

  # Simulate Sentry absent / DSN not configured.
  def with_sentry_inactive
    allow(Sentry).to receive(:initialized?).and_return(false)
    yield
  end

  # -------------------------------------------------------------------------
  # track_exception
  # -------------------------------------------------------------------------

  describe "#track_exception" do
    context "when Sentry is initialized" do
      it "calls Sentry.capture_exception with the exception and enriched context" do
        with_sentry_active do
          expect(Sentry).to receive(:capture_exception).with(
            exception,
            hash_including(extra: hash_including(context.merge(environment: "test")))
          )

          service.track_exception(exception, context)
        end
      end

      it "always logs the exception locally regardless of Sentry state" do
        with_sentry_active do
          allow(Sentry).to receive(:capture_exception)
          allow(Rails.logger).to receive(:error)
          expect(Rails.logger).to receive(:error).with(/RuntimeError - boom/)

          service.track_exception(exception)
        end
      end
    end

    context "when Sentry is NOT initialized (no DSN)" do
      it "does not call Sentry.capture_exception" do
        with_sentry_inactive do
          expect(Sentry).not_to receive(:capture_exception)
          service.track_exception(exception, context)
        end
      end

      it "still logs the exception locally" do
        with_sentry_inactive do
          allow(Rails.logger).to receive(:error)
          expect(Rails.logger).to receive(:error).with(/RuntimeError - boom/)
          service.track_exception(exception)
        end
      end
    end

    context "when the error tracker itself raises" do
      it "rescues and logs without re-raising" do
        with_sentry_active do
          allow(Sentry).to receive(:capture_exception).and_raise(StandardError, "sentry down")
          expect(Rails.logger).to receive(:error).with(/ErrorTrackingService#track_exception failed/)

          expect { service.track_exception(exception) }.not_to raise_error
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # track_message
  # -------------------------------------------------------------------------

  describe "#track_message" do
    context "when Sentry is initialized" do
      it "calls Sentry.capture_message with the message and level" do
        with_sentry_active do
          expect(Sentry).to receive(:capture_message).with(
            "hello",
            hash_including(level: :warn)
          )

          service.track_message("hello", :warn, context)
        end
      end
    end

    context "when Sentry is NOT initialized" do
      it "does not call Sentry.capture_message" do
        with_sentry_inactive do
          expect(Sentry).not_to receive(:capture_message)
          service.track_message("silent", :info)
        end
      end

      it "still logs the message via Rails.logger" do
        with_sentry_inactive do
          expect(Rails.logger).to receive(:info).with(/"message":"silent"/)
          service.track_message("silent", :info)
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # add_breadcrumb
  # -------------------------------------------------------------------------

  describe "#add_breadcrumb" do
    context "when Sentry is initialized" do
      it "calls Sentry.add_breadcrumb with a Sentry::Breadcrumb" do
        with_sentry_active do
          expect(Sentry).to receive(:add_breadcrumb).with(
            an_instance_of(Sentry::Breadcrumb)
          )

          service.add_breadcrumb("user clicked button", category: "ui", level: :info, data: { button: "submit" })
        end
      end
    end

    context "when Sentry is NOT initialized" do
      it "does not call Sentry.add_breadcrumb" do
        with_sentry_inactive do
          expect(Sentry).not_to receive(:add_breadcrumb)
          service.add_breadcrumb("noop breadcrumb")
        end
      end
    end
  end

  # -------------------------------------------------------------------------
  # set_user / set_user_context alias
  # -------------------------------------------------------------------------

  describe "#set_user" do
    let(:user_data) { { id: 1, email: "user@example.com" } }

    context "when Sentry is initialized" do
      it "calls Sentry.set_user with user data" do
        with_sentry_active do
          expect(Sentry).to receive(:set_user).with(user_data)
          service.set_user(user_data)
        end
      end
    end

    context "when Sentry is NOT initialized" do
      it "does not call Sentry.set_user" do
        with_sentry_inactive do
          expect(Sentry).not_to receive(:set_user)
          service.set_user(user_data)
        end
      end
    end
  end

  describe "#set_user_context (alias)" do
    it "delegates to set_user" do
      user_data = { id: 99 }
      with_sentry_active do
        expect(Sentry).to receive(:set_user).with(user_data)
        service.set_user_context(user_data)
      end
    end
  end

  # -------------------------------------------------------------------------
  # track_bulk_operation_error
  # -------------------------------------------------------------------------

  describe "#track_bulk_operation_error" do
    it "calls track_exception with the error and enriched context" do
      with_sentry_active do
        expect(Sentry).to receive(:capture_exception).with(
          exception,
          hash_including(extra: hash_including(
            operation_type: "import",
            subsystem: "bulk_categorization",
            user_id: 42
          ))
        )

        service.track_bulk_operation_error("import", exception, { user_id: 42 })
      end
    end
  end

  # -------------------------------------------------------------------------
  # Class-level delegation (Singleton convenience API)
  # -------------------------------------------------------------------------

  describe ".track_exception (class method delegation)" do
    it "delegates to the singleton instance" do
      with_sentry_active do
        allow(Sentry).to receive(:capture_exception)
        expect(described_class.instance).to receive(:track_exception).with(exception, context).and_call_original

        described_class.track_exception(exception, context)
      end
    end
  end
end
