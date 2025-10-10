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

  describe 'large email handling' do
    describe '#process_large_email' do
      let(:large_content) { "Line %d: Some transaction data\n" }
      let(:full_content) { (1..200).map { |i| large_content % i }.join }

      it 'processes only first 100 lines' do
        result = parser.send(:process_large_email, full_content)
        expect(result).to include('Line 99')
        expect(result).to include('Line 100')
        expect(result).not_to include('Line 101')
      end

      it 'logs warning about large email size' do
        expect(logger).to receive(:warn).with("[EmailProcessing] Large email detected: #{full_content.bytesize} bytes")
        parser.send(:process_large_email, full_content)
      end

      it 'uses StringIO for memory efficiency' do
        stringio = instance_double(StringIO, :<<  => nil, string: 'processed', close: nil)
        allow(StringIO).to receive(:new).and_return(stringio)

        parser.send(:process_large_email, full_content)
        expect(StringIO).to have_received(:new)
      end

      it 'closes StringIO after processing' do
        stringio = StringIO.new
        allow(StringIO).to receive(:new).and_return(stringio)

        parser.send(:process_large_email, full_content)
        expect(stringio).to be_closed
      end

      it 'decodes quoted-printable in each line' do
        encoded_lines = [
          "Line 1: =E2=82=AC100\n",
          "Line 2: =C3=B1=C3=A9\n",
          "Line 3: Normal text\n"
        ]
        content = encoded_lines.join

        result = parser.send(:process_large_email, content)
        expect(result).to include('€100')
        expect(result).to include('ñé')
        expect(result).to include('Normal text')
      end

      it 'forces UTF-8 encoding on result' do
        result = parser.send(:process_large_email, full_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'scrubs invalid UTF-8 sequences' do
        invalid_content = "Valid line\nInvalid: \xFF\xFE\nAnother valid"
        result = parser.send(:process_large_email, invalid_content)
        expect(result).to include('Valid line')
        expect(result).to include('Another valid')
      end

      it 'handles empty content' do
        result = parser.send(:process_large_email, '')
        expect(result).to eq('')
      end

      it 'handles single line' do
        single_line = "Only one line of content"
        result = parser.send(:process_large_email, single_line)
        expect(result).to eq(single_line)
      end

      it 'handles content with no newlines' do
        no_newlines = "Content without any newlines but very long " * 100
        result = parser.send(:process_large_email, no_newlines)
        expect(result).to include('Content without any newlines')
      end
    end

    describe 'MAX_EMAIL_SIZE threshold' do
      it 'has correct MAX_EMAIL_SIZE constant' do
        expect(EmailProcessing::Parser::MAX_EMAIL_SIZE).to eq(50_000)
      end

      it 'has correct TRUNCATE_SIZE constant' do
        expect(EmailProcessing::Parser::TRUNCATE_SIZE).to eq(10_000)
      end

      context 'email size detection' do
        it 'processes as standard when exactly at threshold' do
          content = 'X' * EmailProcessing::Parser::MAX_EMAIL_SIZE
          email_data[:body] = content

          expect(parser).not_to receive(:process_large_email)
          expect(parser).to receive(:process_standard_email).and_call_original
          parser.send(:email_content)
        end

        it 'processes as large when one byte over threshold' do
          content = 'X' * (EmailProcessing::Parser::MAX_EMAIL_SIZE + 1)
          email_data[:body] = content

          expect(parser).to receive(:process_large_email).and_call_original
          expect(parser).not_to receive(:process_standard_email)
          parser.send(:email_content)
        end

        it 'uses bytesize not length for measurement' do
          # Multi-byte characters
          content = '€' * 17_000  # 3 bytes per character = 51,000 bytes
          email_data[:body] = content

          expect(parser).to receive(:process_large_email).and_call_original
          parser.send(:email_content)
        end
      end
    end
  end

  describe 'error scenarios' do
    describe 'nil and empty values' do
      it 'handles nil email body' do
        email_data[:body] = nil
        content = parser.send(:email_content)
        expect(content).to eq('')
      end

      it 'handles missing body key' do
        email_data.delete(:body)
        content = parser.send(:email_content)
        expect(content).to eq('')
      end

      it 'handles empty string body' do
        email_data[:body] = ''
        content = parser.send(:email_content)
        expect(content).to eq('')
      end

      it 'handles whitespace-only body' do
        email_data[:body] = "   \n\t\r\n   "
        content = parser.send(:email_content)
        expect(content.strip).to eq('')
      end
    end

    describe 'encoding errors' do
      it 'handles binary encoded content' do
        binary_content = "\x89PNG\r\n\x1A\n".force_encoding('BINARY')
        email_data[:body] = binary_content

        expect { parser.send(:email_content) }.not_to raise_error
        content = parser.send(:email_content)
        expect(content).to be_a(String)
      end

      it 'handles ASCII-8BIT encoding' do
        ascii_content = "Test content".force_encoding('ASCII-8BIT')
        email_data[:body] = ascii_content

        content = parser.send(:email_content)
        expect(content.encoding).to eq(Encoding::UTF_8)
        expect(content).to eq('Test content')
      end

      it 'handles mixed valid and invalid UTF-8' do
        mixed = "Valid UTF-8 ✓\xFF\xFE Invalid bytes ✗"
        email_data[:body] = mixed.force_encoding('BINARY')

        content = parser.send(:email_content)
        expect(content).to include('Valid UTF-8')
        expect(content).to include('Invalid bytes')
      end

      it 'handles incomplete multibyte sequences' do
        # Incomplete UTF-8 sequence
        incomplete = "Text with incomplete \xE2\x82"
        email_data[:body] = incomplete

        expect { parser.send(:email_content) }.not_to raise_error
      end
    end

    describe 'malformed quoted-printable' do
      it 'handles incomplete hex sequences' do
        malformed = "Text =E2=8 incomplete"
        result = parser.send(:process_standard_email, malformed)
        expect(result).to include('Text')
        expect(result).to include('incomplete')
      end

      it 'handles invalid hex characters' do
        invalid_hex = "Text =GG=ZZ invalid"
        result = parser.send(:process_standard_email, invalid_hex)
        expect(result).to include('Text')
        expect(result).to include('invalid')
      end

      it 'handles lowercase hex sequences' do
        lowercase = "Text =e2=82=ac test"
        result = parser.send(:process_standard_email, lowercase)
        expect(result).to include('Text')
        expect(result).to include('test')
      end

      it 'handles mixed case hex' do
        mixed_case = "Text =E2=82=Ac test"
        result = parser.send(:process_standard_email, mixed_case)
        expect(result).to include('€')
      end

      it 'handles equals sign at end of content' do
        trailing_equals = "Content ends with ="
        result = parser.send(:process_standard_email, trailing_equals)
        expect(result).to eq('Content ends with =')
      end
    end

    describe 'exception handling in create_expense' do
      let(:parsed_data) do
        {
          amount: BigDecimal('100'),
          transaction_date: Date.current,
          merchant_name: 'Test',
          description: 'Test'
        }
      end

      context 'when database operations fail' do
        it 'handles ActiveRecord::RecordNotFound' do
          allow(parser).to receive(:find_duplicate_expense).and_raise(ActiveRecord::RecordNotFound)

          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).not_to be_empty
        end

        it 'handles database connection errors' do
          allow(parser).to receive(:find_duplicate_expense).and_raise(ActiveRecord::ConnectionNotEstablished)

          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).not_to be_empty
        end

        it 'handles timeout errors' do
          allow(parser).to receive(:find_duplicate_expense).and_raise(ActiveRecord::StatementTimeout)

          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).not_to be_empty
        end
      end

      context 'when service integrations fail' do
        let(:expense) { instance_double(Expense,
          save: true,
          update: true,
          description: 'Test',
          merchant_name: 'Test Merchant',
          formatted_amount: '$100.00'
        ) }

        before do
          allow(parser).to receive(:find_duplicate_expense).and_return(nil)
          allow(Expense).to receive(:new).and_return(expense)
          allow(expense).to receive(:category=)
        end

        it 'handles CurrencyDetectorService errors' do
          allow(parser).to receive(:set_currency).and_raise(StandardError, 'Currency detection failed')

          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).to include(/Currency detection failed/)
        end

        it 'handles CategoryGuesserService errors' do
          allow(parser).to receive(:set_currency)
          allow(parser).to receive(:guess_category).and_raise(StandardError, 'Category guess failed')

          expect { parser.send(:create_expense, parsed_data) }.not_to raise_error
          expect(parser.errors).to include(/Category guess failed/)
        end
      end
    end
  end

  describe 'boundary conditions' do
    describe 'email content size boundaries' do
      it 'handles zero-byte content' do
        email_data[:body] = ''
        expect(parser.send(:email_content)).to eq('')
      end

      it 'handles 1-byte content' do
        email_data[:body] = 'X'
        expect(parser.send(:email_content)).to eq('X')
      end

      it 'handles exactly 49,999 bytes (just under threshold)' do
        content = 'X' * 49_999
        email_data[:body] = content

        expect(parser).to receive(:process_standard_email).and_call_original
        parser.send(:email_content)
      end

      it 'handles exactly 50,000 bytes (at threshold)' do
        content = 'X' * 50_000
        email_data[:body] = content

        expect(parser).to receive(:process_standard_email).and_call_original
        parser.send(:email_content)
      end

      it 'handles exactly 50,001 bytes (just over threshold)' do
        content = 'X' * 50_001
        email_data[:body] = content

        expect(parser).to receive(:process_large_email).and_call_original
        parser.send(:email_content)
      end

      it 'handles extremely large emails (1MB+)' do
        content = 'X' * 1_000_000
        email_data[:body] = content

        result = parser.send(:email_content)
        expect(result).to be_a(String)
        expect(result.length).to be < content.length  # Should be truncated
      end
    end

    describe 'line count boundaries for large emails' do
      it 'handles exactly 99 lines' do
        lines = (1..99).map { |i| "Line #{i}" }
        content = lines.join("\n")

        result = parser.send(:process_large_email, content)
        expect(result).to include('Line 99')
      end

      it 'handles exactly 100 lines' do
        lines = (1..100).map { |i| "Line #{i}" }
        content = lines.join("\n")

        result = parser.send(:process_large_email, content)
        expect(result).to include('Line 100')
      end

      it 'handles exactly 101 lines' do
        lines = (1..101).map { |i| "Line #{i}" }
        content = lines.join("\n")

        result = parser.send(:process_large_email, content)
        expect(result).to include('Line 100')
        expect(result).not_to include('Line 101')
      end
    end

    describe 'special characters and edge cases' do
      it 'handles null bytes in content' do
        null_content = "Text\x00with\x00nulls"
        email_data[:body] = null_content

        content = parser.send(:email_content)
        expect(content).to include('Text')
        expect(content).to include('with')
      end

      it 'handles various line endings' do
        mixed_endings = "Line1\rLine2\nLine3\r\nLine4"
        email_data[:body] = mixed_endings

        content = parser.send(:email_content)
        expect(content).to include('Line1')
        expect(content).to include('Line4')
      end

      it 'handles BOM markers' do
        bom_content = "\xEF\xBB\xBFContent with BOM"
        email_data[:body] = bom_content

        content = parser.send(:email_content)
        expect(content).to include('Content with BOM')
      end

      it 'handles control characters' do
        control_chars = "Text\x01\x02\x03\x1F\x7FMore text"
        email_data[:body] = control_chars

        content = parser.send(:email_content)
        expect(content).to include('Text')
        expect(content).to include('More text')
      end
    end
  end

  describe 'unusual input combinations' do
    it 'handles email_data as nil' do
      parser = described_class.new(email_account, nil)
      expect(parser.email_data).to be_nil
      # Accessing email_content would raise an error
      expect { parser.send(:email_content) }.to raise_error(NoMethodError)
    end

    it 'handles email_account as nil' do
      allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(nil)
      parser = described_class.new(nil, email_data)
      expect(parser.email_account).to be_nil
    end

    it 'handles both nil' do
      parser = described_class.new(nil, nil)
      expect(parser.email_account).to be_nil
      expect(parser.email_data).to be_nil
      # Accessing email_content would raise an error
      expect { parser.send(:email_content) }.to raise_error(NoMethodError)
    end

    it 'handles email_data with unexpected keys' do
      weird_data = { unexpected: 'value', body: 'content' }
      parser = described_class.new(email_account, weird_data)
      expect(parser.send(:email_content)).to eq('content')
    end

    it 'handles frozen string in body' do
      frozen_body = 'Frozen content'.freeze
      email_data[:body] = frozen_body

      content = parser.send(:email_content)
      expect(content).to eq('Frozen content')
      expect(content).not_to be_frozen
    end
  end
end
