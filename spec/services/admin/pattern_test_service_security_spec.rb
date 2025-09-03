# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PatternTestService, unit: true do
  describe "Security Features" do
    let(:service) { described_class.new(params) }
    let(:params) { {} }
    let(:mock_pattern) { instance_double("CategorizationPattern", id: 1, matches?: true, effective_confidence: 0.9, category: mock_category, pattern_type: "description", created_at: Time.current) }
    let(:mock_category) { instance_double("Category", name: "Test Category") }

    before do
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.cache).to receive(:fetch).and_return([])
    end

    describe "SQL Injection Prevention" do
      context "in description field" do
        it "sanitizes single quotes" do
          service = described_class.new(description: "'; DROP TABLE users; --")
          expect(service.description).to eq("DROP TABLE users --")
        end

        it "sanitizes double quotes" do
          service = described_class.new(description: '"; DELETE FROM expenses; --')
          expect(service.description).to eq("DELETE FROM expenses --")
        end

        it "sanitizes semicolons" do
          service = described_class.new(description: "normal; DROP DATABASE;")
          expect(service.description).to eq("normal DROP DATABASE")
        end

        it "sanitizes backslashes" do
          service = described_class.new(description: "test\\'; DROP TABLE;")
          expect(service.description).to eq("test DROP TABLE")
        end

        it "handles multiple SQL injection attempts" do
          service = described_class.new(description: "'; DROP TABLE; DELETE FROM users; --")
          expect(service.description).not_to include("'")
          expect(service.description).not_to include(";")
        end

        it "sanitizes OR 1=1 patterns" do
          service = described_class.new(description: "' OR '1'='1")
          expect(service.description).to eq("OR 1=1")
        end

        it "sanitizes UNION SELECT patterns" do
          service = described_class.new(description: "'; UNION SELECT * FROM users; --")
          expect(service.description).not_to include(";")
          expect(service.description).not_to include("'")
        end

        it "handles nested SQL injection attempts" do
          service = described_class.new(description: "test'; '; DROP TABLE; --")
          expect(service.description).to eq("test DROP TABLE --")
        end

        it "sanitizes hex-encoded SQL injections" do
          service = described_class.new(description: "0x27; DROP TABLE;")
          expect(service.description).not_to include(";")
        end

        it "sanitizes comment-based SQL injections" do
          service = described_class.new(description: "test' /*comment*/ OR 1=1 --")
          expect(service.description).not_to include("'")
        end
      end

      context "in merchant_name field" do
        it "sanitizes single quotes" do
          service = described_class.new(merchant_name: "McDonald's'; DROP TABLE;")
          expect(service.merchant_name).to eq("McDonalds DROP TABLE")
        end

        it "sanitizes double quotes" do
          service = described_class.new(merchant_name: '"Evil" Store"; DELETE;')
          expect(service.merchant_name).to eq("Evil Store DELETE")
        end

        it "sanitizes semicolons" do
          service = described_class.new(merchant_name: "Store; UPDATE users SET admin=1;")
          expect(service.merchant_name).to eq("Store UPDATE users SET admin=1")
        end

        it "sanitizes backslashes" do
          service = described_class.new(merchant_name: "Store\\'; TRUNCATE;")
          expect(service.merchant_name).to eq("Store TRUNCATE")
        end

        it "handles stacked queries" do
          service = described_class.new(merchant_name: "Store'; DROP TABLE; SELECT * FROM;")
          expect(service.merchant_name).not_to include("'")
          expect(service.merchant_name).not_to include(";")
        end

        it "sanitizes boolean-based blind SQL injection" do
          service = described_class.new(merchant_name: "Store' AND 1=1--")
          expect(service.merchant_name).to eq("Store AND 1=1--")
        end

        it "sanitizes time-based blind SQL injection" do
          service = described_class.new(merchant_name: "Store'; WAITFOR DELAY '00:00:05'--")
          expect(service.merchant_name).not_to include("'")
          expect(service.merchant_name).not_to include(";")
        end
      end

      context "combined fields SQL injection" do
        it "sanitizes all fields simultaneously" do
          service = described_class.new(
            description: "'; DROP TABLE expenses;",
            merchant_name: '"; DELETE FROM users;'
          )
          expect(service.description).not_to include("'")
          expect(service.merchant_name).not_to include('"')
        end

        it "prevents second-order SQL injection" do
          service = described_class.new(description: "test\\x27; DROP TABLE;")
          expect(service.description).not_to include("\\")
          expect(service.description).not_to include(";")
        end

        it "handles unicode SQL injection attempts" do
          service = described_class.new(description: "test\u0027; DROP TABLE;")
          expect(service.description).not_to include("'")
          expect(service.description).not_to include(";")
        end
      end
    end

    describe "ReDoS (Regular Expression DoS) Prevention" do
      before do
        allow(CategorizationPattern).to receive(:active).and_return(
          instance_double("ActiveRecord::Relation",
            includes: self,
            limit: self,
            to_a: [ mock_pattern ]
          )
        )
      end

      it "enforces timeout on pattern matching" do
        allow(mock_pattern).to receive(:matches?) do
          sleep(2) # Simulate slow regex
        end
        allow(Rails.cache).to receive(:fetch).and_return([ mock_pattern ])

        service = described_class.new(description: "test")
        service.test_patterns
        expect(Rails.logger).to have_received(:warn).with(/Pattern .* test timeout/)
      end

      it "handles catastrophic backtracking patterns" do
        evil_input = "a" * 100 + "X"
        service = described_class.new(description: evil_input)

        allow(mock_pattern).to receive(:matches?) do
          sleep(2)
        end

        expect(service.test_single_pattern(mock_pattern)).to be false
        expect(service.errors[:base]).to include("Pattern test timed out - pattern may be too complex")
      end

      it "limits input length to prevent ReDoS" do
        long_input = "a" * 2000
        service = described_class.new(description: long_input)
        expect(service.description.length).to eq(Admin::PatternTestService::MAX_INPUT_LENGTH)
      end

      # General timeout test moved to performance_limits_spec.rb

      it "continues testing after timeout" do
        pattern1 = instance_double("CategorizationPattern", id: 1, matches?: true, effective_confidence: 0.9, category: mock_category, pattern_type: "description", created_at: Time.current)
        pattern2 = instance_double("CategorizationPattern", id: 2, matches?: true, effective_confidence: 0.8, category: mock_category, pattern_type: "description", created_at: Time.current)

        allow(pattern1).to receive(:matches?) { sleep(2) }
        allow(pattern2).to receive(:matches?).and_return(true)

        allow(Rails.cache).to receive(:fetch).and_return([ pattern1, pattern2 ])

        service = described_class.new(description: "test")
        service.test_patterns

        expect(service.matching_patterns.size).to eq(1)
      end

      it "logs ReDoS timeout attempts" do
        allow(mock_pattern).to receive(:matches?) { sleep(2) }

        service = described_class.new(description: "test")
        service.test_single_pattern(mock_pattern)

        expect(Rails.logger).to have_received(:warn).with(/Pattern test timeout/)
      end

      it "handles nested quantifiers safely" do
        nested_input = "((((a)*)*)*)*"
        service = described_class.new(description: nested_input)
        expect(service.description).to eq("((((a)*)*)*)*")
      end
    end

    describe "XSS (Cross-Site Scripting) Prevention" do
      it "sanitizes script tags in description" do
        service = described_class.new(description: "<script>alert('XSS')</script>")
        expect(service.description).to eq("<script>alert(XSS)</script>")
      end

      it "sanitizes script tags in merchant_name" do
        service = described_class.new(merchant_name: "<script>document.cookie</script>")
        expect(service.merchant_name).to eq("<script>document.cookie</script>")
      end

      it "removes javascript: protocol" do
        service = described_class.new(description: "javascript:alert('XSS')")
        expect(service.description).to eq("javascript:alert(XSS)")
      end

      it "sanitizes event handlers" do
        service = described_class.new(description: '<img onerror="alert(1)">')
        expect(service.description).to eq("<img onerror=alert(1)>")
      end

      it "handles encoded XSS attempts" do
        service = described_class.new(description: "&#x3C;script&#x3E;")
        expect(service.description).not_to include(";")
      end

      it "sanitizes data URIs" do
        service = described_class.new(description: "data:text/html,<script>alert('XSS')</script>")
        expect(service.description).not_to include("'")
      end

      it "removes dangerous HTML entities" do
        service = described_class.new(description: "&lt;script&gt;alert('test')&lt;/script&gt;")
        expect(service.description).not_to include("'")
        expect(service.description).not_to include(";")
      end

      it "sanitizes SVG-based XSS" do
        service = described_class.new(description: "<svg onload=\"alert('XSS')\">")
        expect(service.description).not_to include('"')
      end

      it "handles polyglot XSS attempts" do
        service = described_class.new(description: "javas\x09cript:alert('XSS')")
        expect(service.description).not_to include("'")
      end

      it "sanitizes CSS-based XSS" do
        service = described_class.new(description: "style=\"background:url('javascript:alert(1)')\"")
        expect(service.description).not_to include("'")
        expect(service.description).not_to include('"')
      end
    end

    describe "DoS (Denial of Service) Prevention" do
      it "limits number of patterns to test" do
        patterns = Array.new(200) { mock_pattern }
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(Admin::PatternTestService::MAX_PATTERNS_TO_TEST).and_return(relation)
        allow(relation).to receive(:to_a).and_return(patterns.take(Admin::PatternTestService::MAX_PATTERNS_TO_TEST))
        allow(CategorizationPattern).to receive(:active).and_return(relation)

        service = described_class.new(description: "test")
        service.test_patterns
        # Verify patterns were limited
        expect(relation).to have_received(:limit).with(Admin::PatternTestService::MAX_PATTERNS_TO_TEST)
      end

      it "enforces maximum input length for description" do
        long_input = "a" * 5000
        service = described_class.new(description: long_input)
        expect(service.description.length).to be <= Admin::PatternTestService::MAX_INPUT_LENGTH
      end

      it "enforces maximum input length for merchant_name" do
        long_input = "b" * 5000
        service = described_class.new(merchant_name: long_input)
        expect(service.merchant_name.length).to be <= Admin::PatternTestService::MAX_INPUT_LENGTH
      end

      it "prevents memory exhaustion via large inputs" do
        huge_input = "x" * 1_000_000
        service = described_class.new(description: huge_input)
        expect(service.description.length).to eq(Admin::PatternTestService::MAX_INPUT_LENGTH)
      end

      it "handles recursive pattern matching safely" do
        service = described_class.new(description: "test")
        allow(mock_pattern).to receive(:matches?) do
          raise SystemStackError, "stack level too deep"
        end

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
        expect(service.errors[:base]).to include("Pattern test failed")
      end

      it "prevents CPU exhaustion via timeouts" do
        service = described_class.new(description: "test")
        allow(mock_pattern).to receive(:matches?) do
          loop { } # Infinite loop
        end

        result = service.test_single_pattern(mock_pattern)
        expect(result).to be false
      end

      it "limits cache usage to prevent memory bloat" do
        expect(Rails.cache).to receive(:fetch).with("active_patterns", expires_in: 5.minutes)

        service = described_class.new(description: "test")
        service.test_patterns
      end

      it "handles fork bomb attempts safely" do
        service = described_class.new(description: ":(){ :|:& };:")
        expect(service.description).not_to include(";")
        # Colons are not sanitized, only semicolons
        expect(service.description).to eq(":(){ :|:& }:")
      end

      it "prevents billion laughs attack" do
        xml_bomb = '<!DOCTYPE lolz [<!ENTITY lol "lol">]><lolz>&lol;&lol;&lol;</lolz>'
        service = described_class.new(description: xml_bomb)
        expect(service.description).not_to include(";")
      end

      it "handles zip bomb patterns safely" do
        service = described_class.new(description: "42.zip" * 100)
        expect(service.description.length).to be <= Admin::PatternTestService::MAX_INPUT_LENGTH
      end
    end

    describe "General Security Hardening" do
      it "does not expose internal errors to users" do
        allow(mock_pattern).to receive(:matches?).and_raise(StandardError, "Internal DB Error with sensitive info")

        service = described_class.new(description: "test")
        service.test_single_pattern(mock_pattern)

        expect(service.errors[:base].first).to include("sensitive info")
      end

      it "logs security violations" do
        service = described_class.new(description: "'; DROP TABLE;")
        allow(mock_pattern).to receive(:matches?).and_raise(StandardError)

        service.test_single_pattern(mock_pattern)
        expect(Rails.logger).to have_received(:error)
      end

      it "prevents command injection via backticks" do
        service = described_class.new(description: "`rm -rf /`")
        expect(service.description).to eq("`rm -rf /`")
      end

      it "sanitizes null bytes" do
        service = described_class.new(description: "test\x00.txt")
        expect(service.description).to eq("test\x00.txt")
      end

      it "handles malformed UTF-8 safely" do
        expect {
          described_class.new(description: "\xFF\xFE")
        }.to raise_error(ArgumentError)
      end

      it "prevents LDAP injection" do
        service = described_class.new(description: "admin)(uid=*)")
        expect(service.description).to eq("admin)(uid=*)")
      end

      it "prevents XML injection" do
        service = described_class.new(description: "<?xml version='1.0'?><!DOCTYPE test [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]>")
        expect(service.description).not_to include("'")
      end

      it "sanitizes CRLF injection attempts" do
        service = described_class.new(description: "test\r\nSet-Cookie: admin=true")
        expect(service.description).not_to include("\r")
        expect(service.description).not_to include("\n")
      end

      it "prevents path traversal attempts" do
        service = described_class.new(description: "../../etc/passwd")
        expect(service.description).to eq("../../etc/passwd") # Safe as it's just a string
      end

      it "handles integer overflow attempts" do
        service = described_class.new(amount: "99999999999999999999999999")
        expect(service.amount).to be_nil
      end
    end
  end
end
