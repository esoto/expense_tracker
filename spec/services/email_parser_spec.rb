require 'rails_helper'

RSpec.describe EmailParser, type: :service do
  let(:parsing_rule) { create(:parsing_rule, :bac) }
  let(:email_account) { create(:email_account, :bac) }
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
    EmailParser.new(email_account, email_data)
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

  describe '#initialize' do
    it 'sets email account and email data' do
      parsing_rule  # Ensure parsing rule exists
      parser = EmailParser.new(email_account, email_data)
      expect(parser.email_account).to eq(email_account)
      expect(parser.email_data).to eq(email_data)
      expect(parser.errors).to be_empty
    end

    it 'finds parsing rule for the bank' do
      parsing_rule  # Ensure parsing rule is created first
      parser = EmailParser.new(email_account, email_data)
      expect(parser.parsing_rule).to eq(parsing_rule)
    end

    it 'handles missing parsing rule gracefully' do
      email_account.update(bank_name: 'Unknown Bank')
      parser = EmailParser.new(email_account, email_data)
      expect(parser.parsing_rule).to be_nil
    end
  end

  describe '#parse_expense' do
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
        food_parser = EmailParser.new(email_account, food_email)

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
        invalid_parser = EmailParser.new(email_account, invalid_email)

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
        error_parser = EmailParser.new(email_account, email_data)

        result = error_parser.parse_expense
        expect(result).to be_nil
      end
    end

    # Note: Validation error scenarios are complex to mock properly and are tested in integration
  end

  describe '#test_parsing' do
    context 'with valid parsing rule' do
      it 'returns parsing test results' do
        result = parser.test_parsing
        expect(result[:parsing_rule]).to eq('BAC')
        expect(result[:email_content_preview]).to include('ROGER ESTEBAN')
        expect(result[:pattern_tests]).to be_a(Hash)
        expect(result[:parsed_data]).to be_a(Hash)
      end

      it 'includes pattern test results' do
        result = parser.test_parsing
        pattern_tests = result[:pattern_tests]
        expect(pattern_tests[:amount]).to be_present
        expect(pattern_tests[:date]).to be_present
        expect(pattern_tests[:merchant]).to be_present
        expect(pattern_tests[:description]).to be_present
      end

      it 'limits email content preview' do
        result = parser.test_parsing
        expect(result[:email_content_preview].length).to be <= 201  # Allow for slight variation
      end
    end

    context 'with no parsing rule' do
      before do
        allow(parser).to receive(:parsing_rule).and_return(nil)
      end

      it 'returns error message' do
        result = parser.test_parsing
        expect(result[:error]).to eq('No parsing rule found')
      end
    end

    context 'with parsing errors' do
      it 'returns error message' do
        allow_any_instance_of(ParsingRule).to receive(:test_patterns).and_raise(StandardError, 'Pattern error')

        result = parser.test_parsing
        expect(result[:error]).to eq('Pattern error')
      end
    end
  end

  describe '#email_content' do
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

  describe '#valid_parsed_data?' do
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

  describe '#find_duplicate_expense' do
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

  describe '#set_currency' do
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

  describe '#guess_category' do
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

  describe '#add_error' do
    it 'adds error to errors array' do
      parser.send(:add_error, 'Test error message')
      expect(parser.errors).to include('Test error message')
    end

    it 'logs error with email account context' do
      expect(Rails.logger).to receive(:error).with("[EmailParser] #{email_account.email}: Test error")
      parser.send(:add_error, 'Test error')
    end
  end

  describe 'integration scenarios' do
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
        usd_parser = EmailParser.new(email_account, usd_email)

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
        minimal_parser = EmailParser.new(email_account, minimal_email)

        expense = minimal_parser.parse_expense
        expect(expense).to be_a(Expense)
        expect(expense.amount).to eq(BigDecimal('1500.00'))
        expect(expense.transaction_date).to eq(Date.new(2025, 8, 1))
      end
    end

    context 'error scenarios' do
      it 'handles corrupted email content gracefully' do
        corrupted_email = email_data.merge(body: "\xFF\xFE\x00\x00corrupted")
        corrupted_parser = EmailParser.new(email_account, corrupted_email)

        expect {
          result = corrupted_parser.parse_expense
          expect(result).to be_nil
        }.not_to raise_error
      end

      it 'handles missing email body' do
        empty_email = email_data.merge(body: nil)
        empty_parser = EmailParser.new(email_account, empty_email)

        result = empty_parser.parse_expense
        expect(result).to be_nil
      end
    end
  end
end
