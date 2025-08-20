require 'rails_helper'

RSpec.describe EmailProcessing::Parser, type: :service, performance: true do
  let(:parsing_rule) { create(:parsing_rule, :bac, bank_name: "TEST_BAC_UNIQUE") }
  let(:email_account) { create(:email_account, :bac, bank_name: "TEST_BAC_UNIQUE") }
  let(:category) { create(:category, name: 'Alimentación') }
  let(:email_data) do
    {
      message_id: 123,
      from: 'notifications@bac.net',
      subject: 'Notificación de transacción PTA LEONA SOC 01-08-2025 - 14:16',
      date: 'Wed, 02 Aug 2025 14:16:00 +0000',
      body: sample_bac_email
    }
  end
  let(:parser) {
    parsing_rule  # Ensure parsing rule exists first
    EmailProcessing::Parser.new(email_account, email_data)
  }

  let(:sample_bac_email) do
    <<~EMAIL
      Hola ROGER ESTEBAN SOTO MADRIZ

      Comercio: PTA LEONA SOC Ciudad: SAN JOSE
      Fecha: Ago 1, 2025, 14:16
      Monto: CRC 95,000.00
      Tipo de Transacción: COMPRA

      Si no reconoce esta transacción, comuníquese inmediatamente con BAC.
    EMAIL
  end

  describe '#initialize', performance: true do
    it 'sets email account and email data' do
      parsing_rule  # Ensure parsing rule exists
      parser = EmailProcessing::Parser.new(email_account, email_data)
      expect(parser.email_account).to eq(email_account)
      expect(parser.email_data).to eq(email_data)
      expect(parser.errors).to be_empty
    end

    it 'finds parsing rule for the bank' do
      parsing_rule  # Ensure parsing rule is created first
      parser = EmailProcessing::Parser.new(email_account, email_data)
      expect(parser.parsing_rule).to eq(parsing_rule)
    end

    it 'handles missing parsing rule gracefully' do
      email_account.update(bank_name: 'Unknown Bank')
      parser = EmailProcessing::Parser.new(email_account, email_data)
      expect(parser.parsing_rule).to be_nil
    end
  end

  describe '#parse_expense', performance: true do
    context 'with valid parsing rule and data' do
      before do
        category # ensure category exists
      end

      it 'creates expense successfully' do
        expect {
          result = parser.parse_expense
          expect(result).to be_a(Expense)
          expect(result.amount).to eq(BigDecimal('95000.00'))
          expect(result.transaction_date).to eq(Date.new(2025, 8, 1))
          expect(result.merchant_name).to eq('PTA LEONA SOC')
          expect(result.description).to eq('COMPRA')
          expect(result.status).to eq('processed')
          expect(result.currency).to eq('crc')
        }.to change(Expense, :count).by(1)
      end

      it 'sets raw email content and parsed data' do
        expense = parser.parse_expense
        expect(expense.raw_email_content).to include('PTA LEONA SOC')
        expect(expense.parsed_data).to be_present
        parsed_json = JSON.parse(expense.parsed_data)
        expect(parsed_json['amount']).to eq('95000.0')
        expect(parsed_json['merchant_name']).to eq('PTA LEONA SOC')
      end

      it 'auto-categorizes expense' do
        # Create a category that should match
        food_category = create(:category, name: 'Alimentación')
        # Create new parser with different email content to trigger categorization
        food_email = email_data.merge(
          body: <<~EMAIL
            Comercio: RESTAURANTE LA COCINA Ciudad: SAN JOSE
            Fecha: Ago 1, 2025, 14:16
            Monto: CRC 50,000.00
            Tipo de Transacción: COMPRA
          EMAIL
        )
        parsing_rule  # Ensure parsing rule exists
        food_parser = EmailProcessing::Parser.new(email_account, food_email)

        expense = food_parser.parse_expense
        expect(expense).to be_a(Expense)
        expect(expense.category.name).to eq('Alimentación')
      end
    end

    context 'with no parsing rule' do
      before do
        allow(parser).to receive(:parsing_rule).and_return(nil)
      end

      it 'returns nil' do
        result = parser.parse_expense
        expect(result).to be_nil
      end
    end

    context 'with invalid parsed data' do
      it 'returns nil and adds error when amount is missing' do
        # Create email with completely invalid content that won't parse
        invalid_email = email_data.merge(
          body: <<~EMAIL
            This email has no transaction data
            Just random text
            No amount, no date, nothing useful
          EMAIL
        )
        parsing_rule  # Ensure parsing rule exists
        invalid_parser = EmailProcessing::Parser.new(email_account, invalid_email)

        result = invalid_parser.parse_expense
        expect(result).to be_nil
        expect(invalid_parser.errors).to include('Failed to parse essential expense data')
      end
    end

    context 'with duplicate expense' do
      let!(:existing_expense) do
        create(:expense,
          email_account: email_account,
          amount: BigDecimal('95000.00'),
          transaction_date: Date.new(2025, 8, 1)
        )
      end

      it 'marks existing expense as duplicate' do
        result = parser.parse_expense
        expect(result).to eq(existing_expense)
        expect(existing_expense.reload.status).to eq('duplicate')
        expect(parser.errors).to include('Duplicate expense found')
      end

      it 'does not create new expense' do
        expect {
          parser.parse_expense
        }.not_to change(Expense, :count)
      end
    end

    context 'with parsing errors' do
      it 'handles errors gracefully when parsing rule fails' do
        # Create parser with no parsing rule (will cause error)
        email_account.update(bank_name: 'UNKNOWN_BANK')
        error_parser = EmailProcessing::Parser.new(email_account, email_data)

        result = error_parser.parse_expense
        expect(result).to be_nil
      end
    end

    # Note: Validation error scenarios are complex to mock properly and are tested in integration
  end

  describe '#email_content', performance: true do
    it 'returns cleaned email content' do
      content = parser.send(:email_content)
      expect(content).to include('PTA LEONA SOC')
      expect(content).to include('CRC 95,000.00')
    end

    it 'handles quoted-printable encoding' do
      email_data[:body] = "Comercio: PTA LEONA SOC=\r\nMonto: =E2=82=A195,000.00"
      content = parser.send(:email_content)
      expect(content).to include('Comercio: PTA LEONA SOC')
      expect(content).to include('Monto: ₡95,000.00')
    end

    it 'handles encoding issues' do
      email_data[:body] = "\xFF\xFE Invalid encoding".force_encoding('ASCII-8BIT')
      expect {
        content = parser.send(:email_content)
        expect(content).to be_a(String)
      }.not_to raise_error
    end

    it 'caches content' do
      content1 = parser.send(:email_content)
      content2 = parser.send(:email_content)
      expect(content1).to equal(content2)  # Same object instance
    end
  end

  describe '#valid_parsed_data?', performance: true do
    it 'returns true for data with amount and date' do
      data = { amount: BigDecimal('100.00'), transaction_date: Date.current }
      result = parser.send(:valid_parsed_data?, data)
      expect(result).to be true
    end

    it 'returns false for data missing amount' do
      data = { amount: nil, transaction_date: Date.current }
      result = parser.send(:valid_parsed_data?, data)
      expect(result).to be false
    end

    it 'returns false for data missing transaction_date' do
      data = { amount: BigDecimal('100.00'), transaction_date: nil }
      result = parser.send(:valid_parsed_data?, data)
      expect(result).to be false
    end

    it 'returns false for data missing both amount and date' do
      data = { amount: nil, transaction_date: nil }
      result = parser.send(:valid_parsed_data?, data)
      expect(result).to be false
    end
  end

  describe '#find_duplicate_expense', performance: true do
    let(:parsed_data) do
      {
        amount: BigDecimal('100.00'),
        transaction_date: Date.new(2025, 8, 1)
      }
    end

    context 'with exact match' do
      let!(:existing_expense) do
        create(:expense,
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: Date.new(2025, 8, 1)
        )
      end

      it 'finds duplicate expense' do
        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to eq(existing_expense)
      end
    end

    context 'with date within range' do
      let!(:existing_expense) do
        create(:expense,
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: Date.new(2025, 7, 31)  # Day before, within 1 day range
        )
      end

      it 'finds expense within 1 day range' do
        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to eq(existing_expense)
      end
    end

    context 'with different email account' do
      let!(:existing_expense) do
        create(:expense,
          email_account: create(:email_account, :gmail),
          amount: BigDecimal('100.00'),
          transaction_date: Date.new(2025, 8, 1)
        )
      end

      it 'does not find expense from different account' do
        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to be_nil
      end
    end

    context 'with different amount' do
      let!(:existing_expense) do
        create(:expense,
          email_account: email_account,
          amount: BigDecimal('200.00'),  # Different amount
          transaction_date: Date.new(2025, 8, 1)
        )
      end

      it 'does not find expense with different amount' do
        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to be_nil
      end
    end

    context 'with date outside range' do
      let!(:existing_expense) do
        create(:expense,
          email_account: email_account,
          amount: BigDecimal('100.00'),
          transaction_date: Date.new(2025, 7, 30)  # More than 1 day before
        )
      end

      it 'does not find expense outside date range' do
        result = parser.send(:find_duplicate_expense, parsed_data)
        expect(result).to be_nil
      end
    end
  end

  describe '#set_currency', performance: true do
    let(:expense) { build(:expense, email_account: email_account) }
    let(:parsed_data) { { amount: BigDecimal('100.00') } }

    it 'sets USD currency for dollar amounts' do
      email_data[:body] = 'Total: $100.50 USD charged'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('usd')
    end

    it 'sets EUR currency for euro amounts' do
      email_data[:body] = 'Total: €75.25 EUR charged'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('eur')
    end

    it 'sets CRC currency by default' do
      email_data[:body] = 'Monto: ₡95,000.00'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('crc')
    end

    it 'detects currency from parsed data' do
      parsed_data[:amount] = '$50.00'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('usd')
    end

    it 'detects currency from description' do
      parsed_data[:description] = 'USD Purchase'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('usd')
    end

    it 'detects currency from merchant name' do
      parsed_data[:merchant_name] = 'AMAZON.COM USD'
      parser.send(:set_currency, expense, parsed_data)
      expect(expense.currency).to eq('usd')
    end
  end

  describe '#guess_category', performance: true do
    let(:expense) { build(:expense, email_account: email_account) }

    before do
      create(:category, name: 'Alimentación')
      create(:category, name: 'Transporte')
      create(:category, name: 'Servicios')
      create(:category, name: 'Entretenimiento')
      create(:category, name: 'Salud')
      create(:category, name: 'Compras')
      create(:category, name: 'Sin Categoría')
    end

    it 'categorizes food-related expenses' do
      expense.merchant_name = 'RESTAURANTE LA COCINA'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Alimentación')
    end

    it 'categorizes transport-related expenses' do
      expense.description = 'GASOLINA SHELL'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Transporte')
    end

    it 'categorizes service-related expenses' do
      expense.merchant_name = 'ELECTRICIDAD ICE'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Servicios')
    end

    it 'categorizes entertainment expenses' do
      expense.description = 'CINE MULTIPLEX'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Entretenimiento')
    end

    it 'categorizes health-related expenses' do
      expense.merchant_name = 'FARMACIA SUCRE'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Salud')
    end

    it 'categorizes shopping expenses' do
      expense.description = 'TIENDA LA CURACAO'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Compras')
    end

    it 'handles case insensitive matching' do
      expense.merchant_name = 'SUPER MERCADO CENTRAL'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Alimentación')
    end

    it 'returns default category for unmatched expenses' do
      expense.merchant_name = 'UNKNOWN MERCHANT'
      expense.description = 'UNKNOWN TRANSACTION'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Sin Categoría')
    end

    it 'returns Other category if Sin Categoría not found' do
      Category.find_by(name: 'Sin Categoría').destroy
      create(:category, name: 'Other')

      expense.merchant_name = 'UNKNOWN MERCHANT'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Other')
    end

    it 'returns nil if no default categories exist' do
      Category.where(name: [ 'Sin Categoría', 'Other' ]).destroy_all

      expense.merchant_name = 'UNKNOWN MERCHANT'
      category = parser.send(:guess_category, expense)
      expect(category).to be_nil
    end

    it 'matches multiple keywords' do
      expense.merchant_name = 'RESTAURANTE UBER EATS'
      category = parser.send(:guess_category, expense)
      expect(category.name).to eq('Alimentación')  # Should match restaurant, not transport
    end
  end

  describe '#add_error', performance: true do
    it 'adds error to errors array' do
      parser.send(:add_error, 'Test error message')
      expect(parser.errors).to include('Test error message')
    end

    it 'logs error with email account context' do
      expect(Rails.logger).to receive(:error).with("[EmailProcessing::Parser] #{email_account.email}: Test error")
      parser.send(:add_error, 'Test error')
    end
  end

  describe 'integration scenarios', performance: true do
    context 'complete parsing workflow' do
      before do
        create(:category, name: 'Alimentación')
        create(:category, name: 'Sin Categoría')
      end

      it 'parses USD transaction' do
        usd_email = email_data.merge(
          body: <<~EMAIL
            Comercio: AMAZON.COM Ciudad: SAN JOSE
            Fecha: Aug 1, 2025, 14:16
            Monto: USD 250.75
            Tipo de Transacción: COMPRA
          EMAIL
        )
        parsing_rule  # Ensure parsing rule exists
        usd_parser = EmailProcessing::Parser.new(email_account, usd_email)

        expense = usd_parser.parse_expense
        expect(expense).to be_a(Expense)
        expect(expense.currency).to eq('usd')
        expect(expense.amount).to eq(BigDecimal('250.75'))
      end

      it 'handles parsing rule with nil patterns' do
        parsing_rule.update(merchant_pattern: nil, description_pattern: nil)

        expense = parser.parse_expense
        expect(expense).to be_a(Expense)
        expect(expense.merchant_name).to be_nil
        expect(expense.description).to be_nil
      end

      it 'processes email with minimal required data' do
        minimal_email = email_data.merge(
          body: <<~EMAIL
            Comercio: TEST MERCHANT Ciudad: SAN JOSE
            Monto: CRC 1,500.00
            Fecha: Aug 1, 2025
            Tipo de Transacción: COMPRA
          EMAIL
        )
        parsing_rule  # Ensure parsing rule exists
        minimal_parser = EmailProcessing::Parser.new(email_account, minimal_email)

        expense = minimal_parser.parse_expense
        expect(expense).to be_a(Expense)
        expect(expense.amount).to eq(BigDecimal('1500.00'))
        expect(expense.transaction_date).to eq(Date.new(2025, 8, 1))
      end
    end

    context 'error scenarios' do
      it 'handles corrupted email content gracefully' do
        corrupted_email = email_data.merge(body: "\xFF\xFE\x00\x00corrupted")
        corrupted_parser = EmailProcessing::Parser.new(email_account, corrupted_email)

        expect {
          result = corrupted_parser.parse_expense
          expect(result).to be_nil
        }.not_to raise_error
      end

      it 'handles missing email body' do
        empty_email = email_data.merge(body: nil)
        empty_parser = EmailProcessing::Parser.new(email_account, empty_email)

        result = empty_parser.parse_expense
        expect(result).to be_nil
      end
    end

    context 'additional edge cases' do
      describe '#create_expense error handling', performance: true do
        let(:parsed_data) do
          {
            amount: BigDecimal('100.50'),
            transaction_date: Date.current,
            merchant_name: 'Test Merchant',
            description: 'Test Description'
          }
        end

        it 'handles expense save failure' do
          expense = instance_double(Expense, save: false)
          allow(expense).to receive(:category=)
          allow(expense).to receive(:crc!)
          allow(expense).to receive(:errors).and_return(
            double('errors', full_messages: [ 'Amount cannot be negative' ])
          )
          allow(Expense).to receive(:new).and_return(expense)
          allow(parser).to receive(:find_duplicate_expense).and_return(nil)
          allow(parser).to receive(:set_currency)
          allow(parser).to receive(:guess_category).and_return(nil)

          result = parser.send(:create_expense, parsed_data)

          expect(result).to be_nil
          expect(parser.errors).to include('Failed to save expense: Amount cannot be negative')
        end

        it 'logs successful expense creation' do
          expense = instance_double(Expense,
            save: true,
            update: true,
            formatted_amount: '$100.50'
          )
          allow(expense).to receive(:category=)
          allow(Expense).to receive(:new).and_return(expense)
          allow(parser).to receive(:find_duplicate_expense).and_return(nil)
          allow(parser).to receive(:set_currency)
          allow(parser).to receive(:guess_category).and_return(nil)

          expect(Rails.logger).to receive(:info).with("Created expense: $100.50 from #{email_account.email}")

          result = parser.send(:create_expense, parsed_data)
          expect(result).to eq(expense)
        end
      end

      describe '#set_currency with nil values', performance: true do
        let(:expense) { instance_double(Expense, usd!: nil, eur!: nil, crc!: nil) }

        it 'handles nil values in parsed_data gracefully' do
          parsed_data = { amount: nil, description: nil, merchant_name: nil }

          expect { parser.send(:set_currency, expense, parsed_data) }.not_to raise_error
          expect(expense).to have_received(:crc!)  # Should default to CRC
        end

        it 'handles mixed nil and present values' do
          parsed_data = {
            amount: '$50.00',
            description: nil,
            merchant_name: 'Dollar Store'
          }

          parser.send(:set_currency, expense, parsed_data)
          expect(expense).to have_received(:usd!)
        end
      end

      describe '#guess_category with nil values', performance: true do
        it 'handles expense with nil description and merchant_name' do
          expense = instance_double(Expense, description: nil, merchant_name: nil)

          category = parser.send(:guess_category, expense)

          # Should return default category even with nil values
          expect(category&.name).to be_in([ 'Sin Categoría', 'Other', nil ])
        end

        it 'handles expense with empty strings' do
          expense = instance_double(Expense, description: '', merchant_name: '')

          category = parser.send(:guess_category, expense)

          # Should return default category for empty strings
          expect(category&.name).to be_in([ 'Sin Categoría', 'Other', nil ])
        end
      end

      describe '#email_content edge cases', performance: true do
        it 'handles nil email body' do
          parser.instance_variable_set(:@email_data, { body: nil })

          content = parser.send(:email_content)
          expect(content).to eq('')  # to_s converts nil to empty string
        end

        it 'handles missing body key' do
          parser.instance_variable_set(:@email_data, {})

          content = parser.send(:email_content)
          expect(content).to eq('')  # to_s converts nil to empty string
        end

        it 'handles complex quoted-printable sequences' do
          complex_body = "Test=20with=20spaces=\r\nNew=20line=3D=20equals=E2=82=AC"
          parser.instance_variable_set(:@email_data, { body: complex_body })

          content = parser.send(:email_content)
          expect(content).to include('Test with spaces')
          expect(content).to include('New line= equals€')
        end
      end
    end
  end

  describe 'large email handling', performance: true do
    let(:small_email) { "Small email content" * 100 } # ~1.9KB
    let(:large_email) { "Large email content " * 3000 } # ~60KB

    context 'when email is smaller than MAX_EMAIL_SIZE' do
      it 'processes normally without truncation' do
        email_data[:body] = small_email
        parser = described_class.new(email_account, email_data)

        expect(parser).not_to receive(:process_large_email)
        parser.parse_expense
      end
    end

    context 'when email is larger than MAX_EMAIL_SIZE' do
      it 'processes only first 100 lines' do
        # Create lines that will exceed 50KB
        lines = Array.new(1000) { |i| "Line #{i}: Transaction data with more content to make it larger #{' ' * 100}" }
        email_data[:body] = lines.join("\n")

        parser = described_class.new(email_account, email_data)
        processed_content = parser.send(:email_content)

        # Should contain first 100 lines (0-99)
        expect(processed_content).to include("Line 99")
        expect(processed_content).not_to include("Line 100")
      end

      it 'logs a warning for large emails' do
        email_data[:body] = large_email
        parser = described_class.new(email_account, email_data)

        expect(Rails.logger).to receive(:warn).with(/Large email detected: \d+ bytes/)
        parser.send(:email_content)
      end
    end
  end

  describe 'encoding issues', performance: true do
    context 'with quoted-printable encoding' do
      let(:quoted_printable_content) do
        "Notificaci=C3=B3n de transacci=C3=B3n\r\n" +
        "Monto: =E2=82=A1100.00\r\n" +
        "Descripci=C3=B3n: Caf=C3=A9"
      end

      it 'decodes quoted-printable correctly' do
        email_data[:body] = quoted_printable_content
        parser = described_class.new(email_account, email_data)
        content = parser.send(:email_content)

        expect(content).to include("Notificación de transacción")
        expect(content).to include("₡100.00")
        expect(content).to include("Café")
      end

      it 'handles soft line breaks' do
        content_with_breaks = "This is a very long line that needs to be broken =\r\ninto multiple lines"
        email_data[:body] = content_with_breaks
        parser = described_class.new(email_account, email_data)
        content = parser.send(:email_content)

        expect(content).to eq("This is a very long line that needs to be broken into multiple lines")
      end
    end

    context 'with invalid UTF-8 sequences' do
      it 'scrubs invalid characters' do
        # Create a string with invalid UTF-8 bytes
        invalid_utf8 = "Valid text \xFF\xFE Invalid sequence"
        # Force encoding to binary first to avoid UTF-8 errors
        email_data[:body] = invalid_utf8.force_encoding('BINARY')
        parser = described_class.new(email_account, email_data)

        expect { parser.send(:email_content) }.not_to raise_error
        content = parser.send(:email_content)
        expect(content).to include("Valid text")
      end
    end
  end

  describe 'error handling', performance: true do
    context 'when parsing rule is missing' do
      it 'returns nil when no parsing rule found' do
        # Create a parser with a bank that has no parsing rule
        email_account.update(bank_name: 'NonExistentBank')
        parser_without_rule = described_class.new(email_account, email_data)

        result = parser_without_rule.parse_expense
        expect(result).to be nil
      end
    end

    context 'when strategy raises an error' do
      before do
        allow_any_instance_of(EmailProcessing::Strategies::Regex).to receive(:parse_email).and_raise(StandardError, "Parse error")
      end

      it 'captures the error and returns nil' do
        result = parser.parse_expense
        expect(result).to be nil
        expect(parser.errors).to include("Error parsing email: Parse error")
      end
    end
  end

  describe '#add_error', performance: true do
    it 'logs errors with email account context' do
      expect(Rails.logger).to receive(:error).with("[EmailProcessing::Parser] #{email_account.email}: Test error")
      parser.send(:add_error, "Test error")
    end

    it 'accumulates multiple errors' do
      parser.send(:add_error, "Error 1")
      parser.send(:add_error, "Error 2")
      expect(parser.errors).to eq([ "Error 1", "Error 2" ])
    end
  end

  describe 'performance optimizations', performance: true do
    it 'uses StringIO for memory efficiency in large emails' do
      large_content = "Line\n" * 1000
      email_data[:body] = large_content
      parser = described_class.new(email_account, email_data)

      expect(StringIO).to receive(:new).and_call_original
      parser.send(:process_large_email, large_content)
    end

    it 'closes StringIO after processing' do
      stringio = StringIO.new
      allow(StringIO).to receive(:new).and_return(stringio)

      parser.send(:process_large_email, "content")
      expect(stringio).to be_closed
    end
  end
end
