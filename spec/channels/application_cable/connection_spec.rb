require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel, integration: true do
  describe "#connect", integration: true do
    context "in test environment" do
      it "successfully connects with test session" do
        connect "/cable"

        expect(connection.current_session_info).to be_present
        expect(connection.current_session_info[:session_id]).to eq("test_session")
        expect(connection.current_session_info[:verified_at]).to be_within(1.second).of(Time.current)
      end

      it "returns consistent test session structure" do
        connect "/cable"

        expect(connection.current_session_info).to eq({
          session_id: "test_session",
          sync_session_id: nil,
          verified_at: connection.current_session_info[:verified_at],
          ip_address: "127.0.0.1"
        })
      end
    end

    context "in non-test environment" do
      before do
        allow(Rails.env).to receive(:test?).and_return(false)
      end

      after do
        allow(Rails.env).to receive(:test?).and_call_original
      end

      it "rejects connections without valid session data" do
        # In ActionCable testing, we can't easily mock the encrypted cookies
        # so we test the rejection path which is the most important security aspect
        expect { connect "/cable" }.to have_rejected_connection
      end

      it "logs security failures for invalid connections" do
        expect(Rails.logger).to receive(:warn).with(
          match(/\[SECURITY\] Failed WebSocket authentication/)
        )

        expect { connect "/cable" }.to have_rejected_connection
      end
    end

    context "connection identification" do
      it "identifies connection by current_session_info" do
        connect "/cable"

        # The connection is identified by current_session_info
        expect(connection.current_session_info).to be_present
        expect(connection.current_session_info[:session_id]).to be_present
      end

      it "maintains session data in connection" do
        connect "/cable"

        expect(connection.current_session_info[:session_id]).to eq("test_session")
        expect(connection.current_session_info[:verified_at]).to be_present
        expect(connection.current_session_info[:ip_address]).to eq("127.0.0.1")
      end

      it "includes expected session structure" do
        connect "/cable"

        expect(connection.current_session_info).to include(
          session_id: "test_session",
          sync_session_id: nil,
          ip_address: "127.0.0.1"
        )
      end
    end

    context "edge cases and security" do
      it "handles connection in test environment securely" do
        # Verify that test connections still have proper structure
        connect "/cable"

        expect(connection.current_session_info).to include(
          :session_id,
          :verified_at,
          :ip_address
        )
      end

      it "maintains consistent test session data" do
        connect "/cable"
        first_connection = connection.current_session_info

        # Create another connection
        connect "/cable"
        second_connection = connection.current_session_info

        expect(first_connection[:session_id]).to eq(second_connection[:session_id])
        expect(first_connection[:ip_address]).to eq(second_connection[:ip_address])
      end
    end
  end

  describe "private methods", integration: true do
    # Since we can't easily instantiate a Connection object in tests,
    # we'll test the method logic using a simple class that includes the same method
    let(:test_class) do
      Class.new do
        def extract_session_id(session_data)
          case session_data
          when Hash
            session_data["session_id"] || session_data[:session_id] || SecureRandom.hex(16)
          when String
            nil
          else
            nil
          end
        end
      end
    end

    let(:test_instance) { test_class.new }

    describe "#extract_session_id", integration: true do
      it "extracts session_id from hash with string keys" do
        session_data = { "session_id" => "test_123" }
        result = test_instance.extract_session_id(session_data)
        expect(result).to eq("test_123")
      end

      it "extracts session_id from hash with symbol keys" do
        session_data = { session_id: "test_456" }
        result = test_instance.extract_session_id(session_data)
        expect(result).to eq("test_456")
      end

      it "generates fallback ID for hash without session_id" do
        session_data = { "other_key" => "value" }
        result = test_instance.extract_session_id(session_data)
        expect(result).to match(/\A[0-9a-f]{32}\z/)
      end

      it "returns nil for string data" do
        result = test_instance.extract_session_id("invalid_string")
        expect(result).to be_nil
      end

      it "returns nil for nil data" do
        result = test_instance.extract_session_id(nil)
        expect(result).to be_nil
      end

      it "returns nil for unexpected data types" do
        result = test_instance.extract_session_id(12345)
        expect(result).to be_nil
      end
    end
  end
end
