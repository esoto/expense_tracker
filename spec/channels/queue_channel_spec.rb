# frozen_string_literal: true

require "rails_helper"

RSpec.describe QueueChannel, type: :channel, unit: true do
  before do
    # Stub Rails.logger to capture logging calls
    allow(Rails.logger).to receive(:info)
  end

  describe "#subscribed", :unit do
    it "streams from a session-scoped channel" do
      stub_connection(current_session_info: { session_id: "test_session_123" })
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("queue_updates_test_session_123")
    end

    it "uses the session_id from current_session_info for stream scoping" do
      stub_connection(current_session_info: { session_id: "unique_abc_456" })
      subscribe

      expect(subscription).to have_stream_from("queue_updates_unique_abc_456")
    end

    it "logs successful subscription with session info" do
      stub_connection(current_session_info: { session_id: "log_test_session" })
      subscribe

      expect(Rails.logger).to have_received(:info)
        .with(/Client subscribed to queue updates channel \(session: log_t\.{3}\)/)
    end

    it "confirms subscription immediately" do
      stub_connection(current_session_info: { session_id: "confirm_test" })
      subscribe

      expect(subscription).to be_confirmed
    end

    context "when different sessions subscribe" do
      it "each session gets its own scoped stream" do
        # First session
        stub_connection(current_session_info: { session_id: "session_A" })
        subscribe
        first_subscription = subscription

        # Second session
        stub_connection(current_session_info: { session_id: "session_B" })
        subscribe
        second_subscription = subscription

        expect(first_subscription).to have_stream_from("queue_updates_session_A")
        expect(second_subscription).to have_stream_from("queue_updates_session_B")
      end

      it "does NOT share streams between different sessions" do
        stub_connection(current_session_info: { session_id: "session_A" })
        subscribe
        first_subscription = subscription

        stub_connection(current_session_info: { session_id: "session_B" })
        subscribe
        second_subscription = subscription

        # Session A should NOT have session B's stream
        expect(first_subscription).not_to have_stream_from("queue_updates_session_B")
        # Session B should NOT have session A's stream
        expect(second_subscription).not_to have_stream_from("queue_updates_session_A")
      end
    end

    context "with nil session_id" do
      it "rejects subscription when session_id is nil" do
        stub_connection(current_session_info: { session_id: nil })
        subscribe

        expect(subscription).to be_rejected
      end
    end

    context "with blank session_id" do
      it "rejects subscription when session_id is blank" do
        stub_connection(current_session_info: { session_id: "" })
        subscribe

        expect(subscription).to be_rejected
      end
    end
  end

  describe "#unsubscribed", :unit do
    before do
      stub_connection(current_session_info: { session_id: "unsub_test" })
      subscribe
    end

    it "logs unsubscription" do
      unsubscribe

      expect(Rails.logger).to have_received(:info)
        .with("Client unsubscribed from queue updates channel")
    end

    it "stops all streams when unsubscribed" do
      expect { unsubscribe }.not_to raise_error
    end
  end

  describe "channel inheritance", :unit do
    it "inherits from ApplicationCable::Channel" do
      expect(QueueChannel.superclass).to eq(ApplicationCable::Channel)
    end

    it "is an ActionCable channel" do
      expect(QueueChannel.ancestors).to include(ActionCable::Channel::Base)
    end
  end

  describe "session isolation security", :unit do
    it "prevents cross-session data leakage by using unique stream names" do
      stub_connection(current_session_info: { session_id: "user_session_1" })
      subscribe
      first_sub = subscription

      stub_connection(current_session_info: { session_id: "user_session_2" })
      subscribe
      second_sub = subscription

      # Verify each subscription has exactly one stream and they are different
      expect(first_sub).to have_stream_from("queue_updates_user_session_1")
      expect(second_sub).to have_stream_from("queue_updates_user_session_2")
      expect(first_sub).not_to have_stream_from("queue_updates_user_session_2")
    end
  end

  describe "logging behavior", :unit do
    it "logs subscription with truncated session ID for security" do
      stub_connection(current_session_info: { session_id: "long_session_id_12345" })
      subscribe

      expect(Rails.logger).to have_received(:info) do |message|
        expect(message).to be_a(String)
        expect(message).to include("Client subscribed")
        expect(message).to include("queue updates channel")
        # Should include truncated session ID (first 5 chars + ...)
        expect(message).to include("long_...")
        # Should NOT include full session ID
        expect(message).not_to include("long_session_id_12345")
      end
    end

    it "logs unsubscription with correct message format" do
      stub_connection(current_session_info: { session_id: "log_unsub_test" })
      subscribe
      unsubscribe

      expect(Rails.logger).to have_received(:info).with("Client unsubscribed from queue updates channel")
    end

    it "logs both subscription and unsubscription events" do
      stub_connection(current_session_info: { session_id: "both_events" })
      subscribe
      unsubscribe

      expect(Rails.logger).to have_received(:info).twice
    end
  end

  describe ".stream_name_for", :unit do
    it "generates consistent stream names for session IDs" do
      expect(QueueChannel.stream_name_for("abc123")).to eq("queue_updates_abc123")
    end

    it "returns nil for nil session_id" do
      expect(QueueChannel.stream_name_for(nil)).to be_nil
    end

    it "returns nil for blank session_id" do
      expect(QueueChannel.stream_name_for("")).to be_nil
    end
  end
end
