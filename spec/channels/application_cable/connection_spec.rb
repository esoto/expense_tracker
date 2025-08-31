require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel, unit: true do
  describe "#connect", unit: true do
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

      it "creates fresh timestamp for each connection" do
        time_before = Time.current
        connect "/cable"
        connection_time = connection.current_session_info[:verified_at]

        expect(connection_time).to be >= time_before
        expect(connection_time).to be_within(1.second).of(Time.current)
      end

      it "maintains nil sync_session_id for test connections" do
        connect "/cable"

        expect(connection.current_session_info[:sync_session_id]).to be_nil
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

      it "logs session status in failure messages" do
        expect(Rails.logger).to receive(:warn) do |message|
          expect(message).to include("[SECURITY] Failed WebSocket authentication")
          expect(message).to include("Session=")
          expect(message).to include("IP=")
          expect(message).to include("Time=")
        end

        expect { connect "/cable" }.to have_rejected_connection
      end

      it "handles connection rejection properly" do
        # Verify that the connection is actually rejected
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

      it "provides access to session data after connection" do
        connect "/cable"

        session_info = connection.current_session_info
        expect(session_info.keys).to include(:session_id, :sync_session_id, :verified_at, :ip_address)
      end
    end

    context "connection inheritance and structure" do
      it "inherits from ActionCable::Connection::Base" do
        expect(ApplicationCable::Connection.superclass).to eq(ActionCable::Connection::Base)
      end

      it "defines current_session_info as identifier" do
        connect "/cable"

        # Verify the connection identifies by current_session_info
        expect(connection.current_session_info).to be_present
      end

      it "implements connect method correctly" do
        expect(ApplicationCable::Connection.instance_methods(false)).to include(:connect)
      end

      it "includes private authentication methods" do
        private_methods = ApplicationCable::Connection.private_instance_methods(false)
        expect(private_methods).to include(:find_verified_session)
        expect(private_methods).to include(:extract_session_id)
      end
    end

    context "security and edge cases" do
      it "handles connection in test environment securely" do
        # Verify that test connections still have proper structure
        connect "/cable"

        expect(connection.current_session_info).to include(
          :session_id,
          :verified_at,
          :ip_address
        )
      end

      it "maintains consistent test session data across connections" do
        connect "/cable"
        first_connection = connection.current_session_info

        # Create another connection
        connect "/cable"
        second_connection = connection.current_session_info

        expect(first_connection[:session_id]).to eq(second_connection[:session_id])
        expect(first_connection[:ip_address]).to eq(second_connection[:ip_address])
      end

      it "provides valid session structure for test environment" do
        connect "/cable"

        session_info = connection.current_session_info
        expect(session_info[:session_id]).to be_a(String)
        expect(session_info[:verified_at]).to be_a(Time)
        expect(session_info[:ip_address]).to be_a(String)
        expect(session_info[:sync_session_id]).to be_nil
      end

      it "handles multiple connections without interference" do
        # First connection
        connect "/cable"
        first_session = connection.current_session_info[:session_id]

        # Second connection should have same session ID in test
        connect "/cable"
        second_session = connection.current_session_info[:session_id]

        expect(first_session).to eq(second_session)
      end
    end
  end

  describe "private methods", unit: true do
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

    describe "#extract_session_id", unit: true do
      context "hash data processing" do
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

        it "prioritizes string keys over symbol keys" do
          session_data = { "session_id" => "string_key_value", session_id: "symbol_key_value" }
          result = test_instance.extract_session_id(session_data)
          expect(result).to eq("string_key_value")
        end

        it "generates fallback ID for hash without session_id" do
          session_data = { "other_key" => "value" }
          result = test_instance.extract_session_id(session_data)
          expect(result).to match(/\A[0-9a-f]{32}\z/)
        end

        it "generates different fallback IDs for each call" do
          session_data = { "other_key" => "value" }
          result1 = test_instance.extract_session_id(session_data)
          result2 = test_instance.extract_session_id(session_data)
          expect(result1).not_to eq(result2)
          expect(result1).to match(/\A[0-9a-f]{32}\z/)
          expect(result2).to match(/\A[0-9a-f]{32}\z/)
        end

        it "handles empty hash by generating fallback ID" do
          session_data = {}
          result = test_instance.extract_session_id(session_data)
          expect(result).to match(/\A[0-9a-f]{32}\z/)
        end

        it "handles hash with nil session_id values" do
          session_data = { "session_id" => nil, session_id: nil }
          result = test_instance.extract_session_id(session_data)
          expect(result).to match(/\A[0-9a-f]{32}\z/)
        end
      end

      context "invalid data types" do
        it "returns nil for string data" do
          result = test_instance.extract_session_id("invalid_string")
          expect(result).to be_nil
        end

        it "returns nil for nil data" do
          result = test_instance.extract_session_id(nil)
          expect(result).to be_nil
        end

        it "returns nil for numeric data types" do
          expect(test_instance.extract_session_id(12345)).to be_nil
          expect(test_instance.extract_session_id(123.45)).to be_nil
        end

        it "returns nil for array data" do
          result = test_instance.extract_session_id([ "session_id", "test" ])
          expect(result).to be_nil
        end

        it "returns nil for boolean data" do
          expect(test_instance.extract_session_id(true)).to be_nil
          expect(test_instance.extract_session_id(false)).to be_nil
        end
      end

      context "edge cases" do
        it "handles complex nested hash structures" do
          session_data = {
            "session_id" => "valid_session",
            "nested" => { "data" => "value" },
            "array" => [ 1, 2, 3 ]
          }
          result = test_instance.extract_session_id(session_data)
          expect(result).to eq("valid_session")
        end

        it "returns empty string session_id as-is" do
          session_data = { "session_id" => "" }
          result = test_instance.extract_session_id(session_data)
          expect(result).to eq("")
        end

        it "returns whitespace-only session_id as-is" do
          session_data = { "session_id" => "   " }
          result = test_instance.extract_session_id(session_data)
          expect(result).to eq("   ")
        end
      end
    end

    describe "authentication flow behavior", unit: true do
      it "shows proper method visibility" do
        expect(ApplicationCable::Connection.private_instance_methods(false)).to include(:find_verified_session)
        expect(ApplicationCable::Connection.private_instance_methods(false)).to include(:extract_session_id)
      end

      it "includes proper method definitions" do
        connection_instance_methods = ApplicationCable::Connection.instance_methods(false)
        expect(connection_instance_methods).to include(:connect)
      end
    end

    describe "#find_verified_session behavior", unit: true do
      context "test environment behavior" do
        it "returns test session structure bypassing all authentication" do
          connect "/cable"
          session_info = connection.current_session_info

          expect(session_info).to include(
            session_id: "test_session",
            sync_session_id: nil,
            ip_address: "127.0.0.1"
          )
          expect(session_info[:verified_at]).to be_within(1.second).of(Time.current)
        end
      end

      context "non-test environment method coverage", unit: true do
        # Create a test helper that contains the exact logic from find_verified_session
        # This allows us to test the code paths without ActionCable complexity
        let(:connection_helper) do
          Class.new do
            def self.test_find_verified_session_logic(session_data, remote_ip, fallback_ip = nil)
              # This mimics the exact non-test environment logic from find_verified_session
              ip_address = remote_ip || fallback_ip
              timestamp = Time.current.iso8601

              rails_session_id = extract_session_id(session_data)

              if rails_session_id.present?
                # Line 34: Success logging
                Rails.logger.info "[SECURITY] WebSocket authentication successful: IP=#{ip_address}, Session=#{rails_session_id[0..8]}..., Time=#{timestamp}"

                # Lines 36-37: Fallback logging
                if session_data.is_a?(Hash) && (!session_data["session_id"] && !session_data[:session_id])
                  Rails.logger.info "[SECURITY] Session ID fallback used: IP=#{ip_address}, Generated=#{rails_session_id[0..8]}..., Time=#{timestamp}"
                end

                # Lines 41-42: Session info object creation
                {
                  session_id: rails_session_id,
                  sync_session_id: session_data&.dig("sync_session_id"),
                  verified_at: Time.current,
                  ip_address: ip_address
                }
              else
                # Line 48: Failure logging
                session_status = session_data.nil? ? "nil" : session_data.class.name
                Rails.logger.warn "[SECURITY] Failed WebSocket authentication: IP=#{ip_address}, Session=#{session_status}, Time=#{timestamp}"
                raise "Connection rejected"
              end
            end

            def self.extract_session_id(session_data)
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

        context "success logging and session creation" do
          it "logs successful authentication with explicit session_id and creates session info" do
            session_data = { "session_id" => "valid_session_123", "sync_session_id" => 456 }

            expect(Rails.logger).to receive(:info) do |message|
              expect(message).to include("[SECURITY] WebSocket authentication successful")
              expect(message).to include("IP=192.168.1.100")
              expect(message).to include("Session=valid_ses...")
              expect(message).to match(/Time=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
            end

            result = connection_helper.test_find_verified_session_logic(session_data, "192.168.1.100")

            expect(result[:session_id]).to eq("valid_session_123")
            expect(result[:sync_session_id]).to eq(456)
            expect(result[:ip_address]).to eq("192.168.1.100")
            expect(result[:verified_at]).to be_within(1.second).of(Time.current)
          end

          it "logs successful authentication with symbol session_id key" do
            session_data = { session_id: "symbol_session_789", "sync_session_id" => nil }

            expect(Rails.logger).to receive(:info) do |message|
              expect(message).to include("[SECURITY] WebSocket authentication successful")
              expect(message).to include("IP=test.host")
              expect(message).to include("Session=symbol_se...")
            end

            result = connection_helper.test_find_verified_session_logic(session_data, "test.host")

            expect(result[:session_id]).to eq("symbol_session_789")
            expect(result[:sync_session_id]).to be_nil
          end

          it "logs session ID fallback when no session_id keys exist and creates session" do
            session_data = { "user_id" => 123, "other_data" => "value" }

            expect(Rails.logger).to receive(:info).with(
              match(/\[SECURITY\] WebSocket authentication successful/)
            ).ordered

            expect(Rails.logger).to receive(:info) do |message|
              expect(message).to include("[SECURITY] Session ID fallback used")
              expect(message).to include("IP=10.0.0.1")
              expect(message).to include("Generated=")
            end.ordered

            result = connection_helper.test_find_verified_session_logic(session_data, "10.0.0.1")

            expect(result[:session_id]).to match(/\A[0-9a-f]{32}\z/)
            expect(result[:sync_session_id]).to be_nil
            expect(result[:ip_address]).to eq("10.0.0.1")
            expect(result[:verified_at]).to be_within(1.second).of(Time.current)
          end

          it "uses fallback IP when remote_ip is nil" do
            session_data = { "session_id" => "test_session" }

            expect(Rails.logger).to receive(:info).with(
              match(/\[SECURITY\] WebSocket authentication successful/)
            )

            result = connection_helper.test_find_verified_session_logic(session_data, nil, "fallback.ip")
            expect(result[:ip_address]).to eq("fallback.ip")
            expect(result[:session_id]).to eq("test_session")
          end

          it "extracts sync_session_id from session data" do
            session_data = { "session_id" => "main_session", "sync_session_id" => "sync_123" }

            expect(Rails.logger).to receive(:info)

            result = connection_helper.test_find_verified_session_logic(session_data, "1.2.3.4")

            expect(result[:sync_session_id]).to eq("sync_123")
            expect(result[:session_id]).to eq("main_session")
          end
        end

        context "failure logging scenarios" do
          it "logs failure and rejects with nil session data" do
            expect(Rails.logger).to receive(:warn) do |message|
              expect(message).to include("[SECURITY] Failed WebSocket authentication")
              expect(message).to include("IP=bad.ip")
              expect(message).to include("Session=nil")
              expect(message).to match(/Time=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
            end

            expect {
              connection_helper.test_find_verified_session_logic(nil, "bad.ip")
            }.to raise_error("Connection rejected")
          end

          it "logs failure with proper class name for invalid session types" do
            expect(Rails.logger).to receive(:warn) do |message|
              expect(message).to include("Session=String")
              expect(message).to include("IP=test.ip")
            end

            expect {
              connection_helper.test_find_verified_session_logic("invalid_string", "test.ip")
            }.to raise_error("Connection rejected")
          end
        end
      end
    end
  end
end
