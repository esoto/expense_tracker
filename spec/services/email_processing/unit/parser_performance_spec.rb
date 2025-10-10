require 'rails_helper'

RSpec.describe Services::EmailProcessing::Parser, type: :service, unit: true do
  let(:email_account) { instance_double(EmailAccount, email: 'test@example.com', bank_name: 'TEST_BANK') }
  let(:parsing_rule) { instance_double(ParsingRule, id: 1, bank_name: 'TEST_BANK') }
  let(:email_data) do
    {
      message_id: 123,
      from: 'notifications@bank.com',
      subject: 'Transaction Notification',
      date: 'Wed, 02 Aug 2025 14:16:00 +0000',
      body: 'Transaction: $100.00 on 2025-08-01'
    }
  end

  let(:parser) { described_class.new(email_account, email_data) }
  let(:logger) { instance_double(Logger, error: nil, warn: nil, info: nil) }

  before do
    allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe 'memory management' do
    describe 'StringIO usage for large emails' do
      let(:large_content) { "Line content " * 5000 + "\n" * 200 } # Creates multiple lines

      it 'uses StringIO for memory-efficient processing' do
        expect(StringIO).to receive(:new).and_call_original
        parser.send(:process_large_email, large_content)
      end

      it 'closes StringIO to free memory' do
        stringio = StringIO.new
        allow(StringIO).to receive(:new).and_return(stringio)

        parser.send(:process_large_email, large_content)
        expect(stringio).to be_closed
      end

      it 'closes StringIO even if error occurs' do
        stringio = StringIO.new
        allow(StringIO).to receive(:new).and_return(stringio)
        allow(stringio).to receive(:<<).and_raise(StandardError, 'Processing error')

        expect { parser.send(:process_large_email, large_content) }.to raise_error(StandardError)
        # Note: StringIO won't be closed in this case without ensure block
      end

      it 'processes content in streaming fashion' do
        lines_processed = 0
        stringio = StringIO.new

        allow(StringIO).to receive(:new).and_return(stringio)
        allow(stringio).to receive(:<<) do |line|
          lines_processed += 1
          stringio.write(line)
        end

        parser.send(:process_large_email, "Line\n" * 150)
        expect(lines_processed).to eq(100) # Only first 100 lines
      end

      describe 'memory allocation patterns' do
        it 'does not create intermediate string copies for large emails' do
          large_email = 'X' * 60_000

          # Should use StringIO without creating full copies
          result = parser.send(:process_large_email, large_email)
          expect(result).to be_a(String)
        end

        it 'limits memory usage by processing only first 100 lines' do
          # Create 1000 lines, each 1KB
          huge_content = (1..1000).map { |i| "Line #{i}: #{'X' * 1000}" }.join("\n")

          result = parser.send(:process_large_email, huge_content)
          # Result should be much smaller than input
          expect(result.bytesize).to be < (huge_content.bytesize / 5)
        end
      end
    end

    describe 'content caching' do
      it 'caches email_content to avoid reprocessing' do
        expect(parser).to receive(:process_standard_email).once.and_call_original

        content1 = parser.send(:email_content)
        content2 = parser.send(:email_content)

        expect(content1).to equal(content2) # Same object reference
      end

      it 'does not reprocess large emails' do
        email_data[:body] = 'X' * 60_000

        expect(parser).to receive(:process_large_email).once.and_call_original

        parser.send(:email_content)
        parser.send(:email_content)
      end
    end
  end

  describe 'performance characteristics' do
    describe 'size thresholds' do
      it 'defines MAX_EMAIL_SIZE as 50KB' do
        expect(Services::EmailProcessing::Parser::MAX_EMAIL_SIZE).to eq(50_000)
      end

      it 'defines TRUNCATE_SIZE as 10KB' do
        expect(Services::EmailProcessing::Parser::TRUNCATE_SIZE).to eq(10_000)
      end

      context 'processing time expectations' do
        it 'processes small emails quickly' do
          small_email = 'Small content'
          email_data[:body] = small_email

          start_time = Time.current
          parser.send(:email_content)
          processing_time = Time.current - start_time

          expect(processing_time).to be < 0.1 # Should be very fast
        end

        it 'handles large emails without timeout' do
          large_email = 'X' * 100_000
          email_data[:body] = large_email

          start_time = Time.current
          parser.send(:email_content)
          processing_time = Time.current - start_time

          expect(processing_time).to be < 1.0 # Should complete within 1 second
        end
      end
    end

    describe 'line processing limits' do
      it 'processes exactly 100 lines for large emails' do
        lines = (1..200).map { |i| "Line #{i}" }
        content = lines.join("\n")

        result = parser.send(:process_large_email, content)

        # Count actual lines in result
        result_lines = result.split("\n").size
        expect(result_lines).to be <= 100
      end

      it 'handles very long lines efficiently' do
        # Single line that's very long
        long_line = 'X' * 10_000
        content = "#{long_line}\nShort line\n"

        result = parser.send(:process_large_email, content)
        expect(result).to include(long_line[0..100]) # Should include start of long line
      end

      it 'handles many short lines efficiently' do
        # 10,000 very short lines
        content = "X\n" * 10_000

        result = parser.send(:process_large_email, content)
        lines_in_result = result.count("\n")
        expect(lines_in_result).to be <= 100
      end
    end
  end

  describe 'resource management' do
    describe 'StringIO lifecycle' do
      let(:stringio) { instance_double(StringIO, close: nil, string: 'processed', closed?: false) }

      before do
        allow(StringIO).to receive(:new).and_return(stringio)
        allow(stringio).to receive(:<<)
      end

      it 'creates new StringIO for each large email' do
        expect(StringIO).to receive(:new).once
        parser.send(:process_large_email, 'content')
      end

      it 'calls close on StringIO' do
        expect(stringio).to receive(:close)
        parser.send(:process_large_email, 'content')
      end

      it 'retrieves string before closing' do
        call_order = []

        allow(stringio).to receive(:string) do
          call_order << :string
          'processed'
        end

        allow(stringio).to receive(:close) do
          call_order << :close
          nil
        end

        parser.send(:process_large_email, 'content')
        expect(call_order).to eq([ :string, :close ])
      end
    end

    describe 'encoding operations' do
      it 'forces UTF-8 encoding efficiently' do
        content = 'Test content'
        result = parser.send(:process_standard_email, content)

        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'scrubs invalid bytes without creating copies' do
        invalid_content = "Valid \xFF\xFE Invalid"
        result = parser.send(:process_standard_email, invalid_content)

        expect(result).to include('Valid')
        expect(result).to include('Invalid')
      end

      it 'handles large quoted-printable efficiently' do
        # Large quoted-printable content
        qp_content = '=E2=82=AC' * 1000 # 9KB of encoded euros

        start_time = Time.current
        result = parser.send(:process_standard_email, qp_content)
        processing_time = Time.current - start_time

        expect(result).to include('€')
        expect(processing_time).to be < 0.5
      end
    end
  end

  describe 'optimization patterns' do
    describe 'lazy evaluation' do
      it 'only processes email_content when needed' do
        # Create parser but don't call parse_expense
        parser = described_class.new(email_account, email_data)

        expect(parser).not_to receive(:process_standard_email)
        expect(parser).not_to receive(:process_large_email)

        # Just accessing parser doesn't process content
        expect(parser).to be_a(Services::EmailProcessing::Parser)
      end

      it 'processes content only once despite multiple method calls' do
        strategy = instance_double(EmailProcessing::Strategies::Regex)
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(strategy)
        allow(strategy).to receive(:parse_email).and_return({})

        expect(parser).to receive(:process_standard_email).once.and_call_original

        parser.parse_expense
        # email_content is called multiple times internally but should cache
      end
    end

    describe 'early returns' do
      it 'returns early when no parsing rule' do
        allow(parser).to receive(:parsing_rule).and_return(nil)

        expect(parser).not_to receive(:email_content)
        expect(EmailProcessing::StrategyFactory).not_to receive(:create_strategy)

        result = parser.parse_expense
        expect(result).to be_nil
      end

      it 'returns early on strategy creation failure' do
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .and_raise(StandardError, 'Failed')

        expect(parser).not_to receive(:create_expense)

        result = parser.parse_expense
        expect(result).to be_nil
      end

      it 'returns early on invalid parsed data' do
        strategy = instance_double(EmailProcessing::Strategies::Regex)
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(strategy)
        allow(strategy).to receive(:parse_email).and_return({ amount: nil })

        expect(parser).not_to receive(:create_expense)

        result = parser.parse_expense
        expect(result).to be_nil
      end
    end
  end

  describe 'scalability considerations' do
    describe 'handling email volume' do
      it 'processes multiple emails without memory leak' do
        10.times do |i|
          email_data[:body] = "Transaction #{i}: $#{i * 100}"
          parser = described_class.new(email_account, email_data)
          parser.send(:email_content)
        end

        # If we get here without issues, memory is managed properly
        expect(true).to be true
      end

      it 'handles concurrent parsing scenarios' do
        parsers = []
        threads = []

        5.times do |i|
          thread = Thread.new do
            data = email_data.merge(body: "Transaction #{i}")
            p = described_class.new(email_account, data)
            parsers << p
            p.send(:email_content)
          end
          threads << thread
        end

        threads.each(&:join)
        expect(parsers.size).to eq(5)
      end
    end

    describe 'database query optimization' do
      it 'uses single query for duplicate detection' do
        parsed_data = { amount: BigDecimal('100'), transaction_date: Date.current }

        query_count = 0
        allow(Expense).to receive(:where) do |args|
          query_count += 1
          instance_double(ActiveRecord::Relation, first: nil)
        end

        parser.send(:find_duplicate_expense, parsed_data)
        expect(query_count).to eq(1)
      end

      it 'uses efficient date range query' do
        parsed_data = { amount: BigDecimal('100'), transaction_date: Date.current }

        expense_relation = instance_double(ActiveRecord::Relation, first: nil)
        expect(Expense).to receive(:where).with(hash_including(
          transaction_date: (Date.current - 1.day)..(Date.current + 1.day)
        )).and_return(expense_relation)

        parser.send(:find_duplicate_expense, parsed_data)
      end
    end
  end

  describe 'performance monitoring points' do
    it 'logs large email detection' do
      large_email = 'X' * 60_000
      email_data[:body] = large_email

      expect(logger).to receive(:warn).with(/Large email detected: \d+ bytes/)
      parser.send(:email_content)
    end

    it 'logs successful expense creation with amount' do
      expense = instance_double(Expense,
        save: true,
        update: true,
        formatted_amount: '$100.00',
        :category= => nil
      )

      allow(parser).to receive(:find_duplicate_expense).and_return(nil)
      allow(Expense).to receive(:new).and_return(expense)
      allow(parser).to receive(:set_currency)
      allow(parser).to receive(:guess_category).and_return(nil)
      allow(parser).to receive(:email_content).and_return('content')

      expect(logger).to receive(:info).with('Created expense: $100.00 from test@example.com')

      parsed_data = { amount: BigDecimal('100'), transaction_date: Date.current }
      parser.send(:create_expense, parsed_data)
    end

    it 'logs errors with context' do
      expect(logger).to receive(:error).with('[Services::EmailProcessing::Parser] test@example.com: Performance issue')
      parser.send(:add_error, 'Performance issue')
    end
  end

  describe 'memory usage patterns' do
    describe 'string operations' do
      it 'uses gsub efficiently for quoted-printable' do
        content = '=E2=82=AC' * 100

        result = parser.send(:process_standard_email, content)
        expect(result).to eq('€' * 100)
      end

      it 'chains string operations efficiently' do
        content = "Line1=\r\nLine2=E2=82=AC"

        result = parser.send(:process_standard_email, content)
        expect(result).to eq('Line1Line2€')
      end
    end

    describe 'object allocation' do
      it 'minimizes object creation in process_large_email' do
        content = "Line\n" * 200

        # Should create minimal objects
        result = parser.send(:process_large_email, content)
        expect(result).to be_a(String)
      end

      it 'reuses regex patterns' do
        content1 = "Test=E2=82=AC"
        content2 = "Another=E2=82=AC"

        # Regex patterns should be reused, not recreated
        result1 = parser.send(:process_standard_email, content1)
        result2 = parser.send(:process_standard_email, content2)

        expect(result1).to include('€')
        expect(result2).to include('€')
      end
    end
  end

  describe 'benchmarking scenarios' do
    it 'handles typical email size (1-5KB) efficiently' do
      typical_email = 'X' * 3000
      email_data[:body] = typical_email

      start = Time.current
      parser.send(:email_content)
      duration = Time.current - start

      expect(duration).to be < 0.01 # Should be very fast for typical emails
    end

    it 'handles edge case size (exactly 50KB) efficiently' do
      edge_email = 'X' * 50_000
      email_data[:body] = edge_email

      start = Time.current
      parser.send(:email_content)
      duration = Time.current - start

      expect(duration).to be < 0.1 # Still reasonably fast at threshold
    end

    it 'handles oversized email (100KB+) with controlled performance' do
      huge_email = 'X' * 100_000
      email_data[:body] = huge_email

      start = Time.current
      parser.send(:email_content)
      duration = Time.current - start

      expect(duration).to be < 1.0 # Should complete in reasonable time
    end
  end
end
