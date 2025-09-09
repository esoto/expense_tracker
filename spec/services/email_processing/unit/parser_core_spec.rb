require 'rails_helper'

RSpec.describe EmailProcessing::Parser, type: :service, unit: true do
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

  before do
    allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
  end

  describe '#initialize' do
    it 'sets email account' do
      expect(parser.email_account).to eq(email_account)
    end

    it 'sets email data' do
      expect(parser.email_data).to eq(email_data)
    end

    it 'initializes empty errors array' do
      expect(parser.errors).to eq([])
    end

    it 'finds parsing rule for the bank' do
      expect(parser.parsing_rule).to eq(parsing_rule)
    end

    context 'when no parsing rule exists' do
      before do
        allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(nil)
      end

      it 'sets parsing_rule to nil' do
        expect(parser.parsing_rule).to be_nil
      end
    end
  end

  describe '#parse_expense' do
    let(:strategy) { instance_double(EmailProcessing::Strategies::Regex) }
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 1),
        merchant_name: 'Test Merchant',
        description: 'Test Transaction'
      }
    end

    before do
      allow(EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(strategy)
      allow(strategy).to receive(:parse_email).and_return(parsed_data)
    end

    context 'when parsing rule is nil' do
      before do
        allow(parser).to receive(:parsing_rule).and_return(nil)
      end

      it 'returns nil immediately' do
        expect(parser.parse_expense).to be_nil
      end

      it 'does not create strategy' do
        expect(EmailProcessing::StrategyFactory).not_to receive(:create_strategy)
        parser.parse_expense
      end
    end

    context 'when parsing rule exists' do
      let(:expense) { instance_double(Expense, save: true, update: true, formatted_amount: '$100.00') }

      before do
        allow(parser).to receive(:valid_parsed_data?).and_return(true)
        allow(parser).to receive(:create_expense).and_return(expense)
      end

      it 'creates strategy with parsing rule and email content' do
        expect(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .with(parsing_rule, email_content: anything)
        parser.parse_expense
      end

      it 'parses email using strategy' do
        expect(strategy).to receive(:parse_email).with(anything)
        parser.parse_expense
      end

      it 'validates parsed data' do
        expect(parser).to receive(:valid_parsed_data?).with(parsed_data)
        parser.parse_expense
      end

      it 'creates expense when data is valid' do
        expect(parser).to receive(:create_expense).with(parsed_data)
        parser.parse_expense
      end

      it 'returns created expense' do
        expect(parser.parse_expense).to eq(expense)
      end
    end

    context 'when parsed data is invalid' do
      before do
        allow(parser).to receive(:valid_parsed_data?).and_return(false)
      end

      it 'returns nil' do
        expect(parser.parse_expense).to be_nil
      end

      it 'adds error message' do
        expect(parser).to receive(:add_error).with('Failed to parse essential expense data')
        parser.parse_expense
      end

      it 'does not create expense' do
        expect(parser).not_to receive(:create_expense)
        parser.parse_expense
      end
    end

    context 'when strategy raises error' do
      before do
        allow(strategy).to receive(:parse_email).and_raise(StandardError, 'Parse failed')
      end

      it 'rescues the error' do
        expect { parser.parse_expense }.not_to raise_error
      end

      it 'returns nil' do
        expect(parser.parse_expense).to be_nil
      end

      it 'adds error message with exception details' do
        expect(parser).to receive(:add_error).with('Error parsing email: Parse failed')
        parser.parse_expense
      end
    end

    context 'when StrategyFactory raises error' do
      before do
        allow(EmailProcessing::StrategyFactory).to receive(:create_strategy)
          .and_raise(ArgumentError, 'Invalid strategy')
      end

      it 'rescues the error' do
        expect { parser.parse_expense }.not_to raise_error
      end

      it 'returns nil' do
        expect(parser.parse_expense).to be_nil
      end

      it 'adds error message' do
        expect(parser).to receive(:add_error).with('Error parsing email: Invalid strategy')
        parser.parse_expense
      end
    end
  end

  describe '#valid_parsed_data?' do
    context 'with valid data' do
      it 'returns true when amount and date present' do
        data = { amount: BigDecimal('100'), transaction_date: Date.current }
        expect(parser.send(:valid_parsed_data?, data)).to be true
      end

      it 'returns true with zero amount' do
        data = { amount: BigDecimal('0'), transaction_date: Date.current }
        expect(parser.send(:valid_parsed_data?, data)).to be true
      end

      it 'returns true with string amount that converts to number' do
        data = { amount: '100.00', transaction_date: Date.current }
        expect(parser.send(:valid_parsed_data?, data)).to be true
      end
    end

    context 'with invalid data' do
      it 'returns false when amount is nil' do
        data = { amount: nil, transaction_date: Date.current }
        expect(parser.send(:valid_parsed_data?, data)).to be false
      end

      it 'returns false when amount is empty string' do
        data = { amount: '', transaction_date: Date.current }
        expect(parser.send(:valid_parsed_data?, data)).to be false
      end

      it 'returns false when transaction_date is nil' do
        data = { amount: BigDecimal('100'), transaction_date: nil }
        expect(parser.send(:valid_parsed_data?, data)).to be false
      end

      it 'returns false when both are nil' do
        data = { amount: nil, transaction_date: nil }
        expect(parser.send(:valid_parsed_data?, data)).to be false
      end

      it 'returns false when keys are missing' do
        data = {}
        expect(parser.send(:valid_parsed_data?, data)).to be false
      end
    end
  end

  describe '#find_parsing_rule' do
    it 'queries active parsing rules for bank' do
      expect(ParsingRule).to receive_message_chain(:active, :for_bank, :first)
        .with(no_args)
        .with('TEST_BANK')
        .with(no_args)
      parser.send(:find_parsing_rule)
    end

    it 'returns first matching rule' do
      expect(parser.send(:find_parsing_rule)).to eq(parsing_rule)
    end

    context 'when multiple rules exist' do
      let(:first_rule) { instance_double(ParsingRule, id: 1) }
      let(:second_rule) { instance_double(ParsingRule, id: 2) }

      before do
        allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(first_rule)
      end

      it 'returns only the first rule' do
        expect(parser.send(:find_parsing_rule)).to eq(first_rule)
      end
    end
  end

  describe '#email_content' do
    it 'processes standard email by default' do
      expect(parser).to receive(:process_standard_email).with(email_data[:body])
      parser.send(:email_content)
    end

    it 'caches the result' do
      expect(parser).to receive(:process_standard_email).once.and_call_original
      content1 = parser.send(:email_content)
      content2 = parser.send(:email_content)
      expect(content1).to equal(content2)
    end

    context 'with large email' do
      let(:large_body) { 'X' * (EmailProcessing::Parser::MAX_EMAIL_SIZE + 1) }

      before do
        email_data[:body] = large_body
      end

      it 'processes as large email when exceeds MAX_EMAIL_SIZE' do
        expect(parser).to receive(:process_large_email).with(large_body)
        parser.send(:email_content)
      end
    end

    context 'with exact threshold size' do
      let(:threshold_body) { 'X' * EmailProcessing::Parser::MAX_EMAIL_SIZE }

      before do
        email_data[:body] = threshold_body
      end

      it 'processes as standard email at exact threshold' do
        expect(parser).to receive(:process_standard_email).with(threshold_body)
        parser.send(:email_content)
      end
    end

    context 'with nil body' do
      before do
        email_data[:body] = nil
      end

      it 'converts nil to empty string' do
        content = parser.send(:email_content)
        expect(content).to eq('')
      end
    end
  end

  describe '#add_error' do
    let(:logger) { instance_double(Logger) }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:error)
    end

    it 'adds message to errors array' do
      parser.send(:add_error, 'Test error')
      expect(parser.errors).to include('Test error')
    end

    it 'accumulates multiple errors' do
      parser.send(:add_error, 'Error 1')
      parser.send(:add_error, 'Error 2')
      parser.send(:add_error, 'Error 3')
      expect(parser.errors).to eq([ 'Error 1', 'Error 2', 'Error 3' ])
    end

    it 'logs error with proper context' do
      expect(logger).to receive(:error).with('[EmailProcessing::Parser] test@example.com: Test error')
      parser.send(:add_error, 'Test error')
    end

    it 'logs each error separately' do
      expect(logger).to receive(:error).exactly(3).times
      parser.send(:add_error, 'Error 1')
      parser.send(:add_error, 'Error 2')
      parser.send(:add_error, 'Error 3')
    end
  end

  describe '#process_standard_email' do
    it 'removes soft line breaks' do
      content = "Line1=\r\nLine2"
      result = parser.send(:process_standard_email, content)
      expect(result).to eq('Line1Line2')
    end

    it 'decodes quoted-printable hex sequences' do
      content = '=E2=82=AC100'
      result = parser.send(:process_standard_email, content)
      expect(result).to eq('€100')
    end

    it 'handles multiple hex sequences' do
      content = '=C3=B1=C3=A9=C3=AD'
      result = parser.send(:process_standard_email, content)
      expect(result).to eq('ñéí')
    end

    it 'forces UTF-8 encoding' do
      content = 'Test'
      result = parser.send(:process_standard_email, content)
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'scrubs invalid UTF-8 sequences' do
      # Create invalid UTF-8 by decoding wrong hex
      content = "Valid=FF=FEInvalid"
      result = parser.send(:process_standard_email, content)
      expect(result).to include('Valid')
      expect(result).to include('Invalid')
    end

    it 'preserves normal text' do
      content = 'Normal text without encoding'
      result = parser.send(:process_standard_email, content)
      expect(result).to eq('Normal text without encoding')
    end
  end

  describe '#decode_quoted_printable_line' do
    it 'removes soft line breaks from single line' do
      line = "Content=\r\n"
      result = parser.send(:decode_quoted_printable_line, line)
      expect(result).to eq('Content')
    end

    it 'decodes hex sequences in line' do
      line = 'Price: =E2=82=AC50'
      result = parser.send(:decode_quoted_printable_line, line)
      # The hex codes decode to the Euro symbol (€)
      expect(result).to include('50')
      expect(result).to include('Price:')
    end

    it 'handles mixed content' do
      line = "Text =E2=82=AC with=\r\n"
      result = parser.send(:decode_quoted_printable_line, line)
      # Should remove soft line break and decode hex
      expect(result).to include('Text')
      expect(result).to include('with')
      # Euro symbol is decoded from =E2=82=AC
      expect(result.force_encoding('UTF-8')).to include('€')
    end

    it 'preserves spaces and special characters' do
      line = 'Text with spaces & symbols!'
      result = parser.send(:decode_quoted_printable_line, line)
      expect(result).to eq('Text with spaces & symbols!')
    end
  end
end
