# Test Data Helpers
# Provides utilities for creating realistic test data and scenarios

module TestDataHelpers
  # Email generation helpers
  def generate_bac_transaction_email(amount:, business:, date: Date.current, currency: 'CRC')
    symbol = currency == 'USD' ? '$' : '₡'
    formatted_amount = format_amount(amount, currency)

    "Estimado Cliente, Compra realizada por #{symbol}#{formatted_amount} en #{business.upcase} " \
    "el #{date.strftime('%d/%m/%Y')} a las #{Time.current.strftime('%H:%M')}. " \
    "Su saldo disponible es #{symbol}#{format_amount(rand(100000..500000), currency)}. BAC"
  end

  def generate_bcr_transaction_email(amount:, business:, date: Date.current, currency: 'CRC')
    symbol = currency == 'USD' ? '$' : '₡'
    formatted_amount = format_amount(amount, currency)

    if currency == 'USD'
      "Compra Internacional: #{business} #{symbol}#{formatted_amount} #{date.strftime('%d/%m/%Y')} T.C: ₡525.30"
    else
      "BCR Aviso: Compra POS #{symbol}#{formatted_amount} #{business} #{date.strftime('%d/%m/%Y')} " \
      "#{Time.current.strftime('%H:%M')} Aprobada. Saldo: #{symbol}#{format_amount(rand(50000..300000), currency)}"
    end
  end

  def generate_invalid_email
    [
      "Su estado de cuenta está disponible en línea",
      "Promoción especial para clientes preferenciales",
      "Mantenimiento programado en nuestros sistemas",
      "Notificación de seguridad - verifique sus datos"
    ].sample
  end

  def create_email_batch(account:, count:, valid_ratio: 0.8, date_range: 7.days)
    emails = []
    valid_count = (count * valid_ratio).to_i

    # Generate valid transaction emails
    valid_count.times do
      amount = rand(1000..50000)
      business = sample_businesses.sample
      date = rand(date_range.ago..Time.current).to_date
      currency = account.bank_name == 'BAC' && rand < 0.3 ? 'USD' : 'CRC'

      email = case account.bank_name
      when 'BAC' then generate_bac_transaction_email(amount: amount, business: business, date: date, currency: currency)
      when 'BCR' then generate_bcr_transaction_email(amount: amount, business: business, date: date, currency: currency)
      else "Transacción por #{currency == 'USD' ? '$' : '₡'}#{amount} en #{business}"
      end

      emails << email
    end

    # Generate invalid emails
    (count - valid_count).times do
      emails << generate_invalid_email
    end

    emails.shuffle
  end

  def sample_businesses
    [
      'AUTOMERCADO', 'MAS X MENOS', 'WALMART', 'PRICESMART',
      'MCDONALDS', 'PIZZA HUT', 'SUBWAY', 'TACO BELL',
      'DELTA GASOLINERA', 'UNO GASOLINERA', 'SERVICENTRO',
      'FARMACIA FISCHEL', 'FARMACIA SUCRE', 'CINEPOLIS',
      'AMAZON.COM', 'NETFLIX.COM', 'SPOTIFY', 'APPLE.COM'
    ]
  end

  # Expense data helpers
  def create_monthly_expenses(account:, month:, count: nil)
    start_date = month.beginning_of_month
    end_date = month.end_of_month
    count ||= rand(20..50)

    count.times.map do
      amount = generate_realistic_amount
      currency = account.bank_name == 'BAC' && rand < 0.2 ? 'USD' : 'CRC'

      create(:expense,
        email_account: account,
        amount: amount,
        currency: currency,
        description: generate_realistic_description(account.bank_name, amount, currency),
        created_at: rand(start_date..end_date),
        category: sample_category
      )
    end
  end

  def generate_realistic_amount
    # Distribution mimics real spending patterns
    case rand(1..10)
    when 1..5 then rand(1000..10000)      # 50% small expenses
    when 6..8 then rand(10000..50000)     # 30% medium expenses
    when 9 then rand(50000..150000)       # 10% large expenses
    else rand(150000..500000)             # 10% very large expenses
    end
  end

  def sample_category
    return Category.all.sample if Category.exists?

    create(:category, name: [ 'Alimentación', 'Transporte', 'Entretenimiento', 'Compras', 'Servicios' ].sample)
  end

  # Sync session helpers
  def create_realistic_sync_session(accounts: nil, status: :running)
    accounts ||= EmailAccount.active.limit(3)

    sync_session = create(:sync_session, status.to_s,
                         started_at: rand(1..30).minutes.ago)

    accounts.each do |account|
      total_emails = rand(50..300)
      processed = case status
      when :pending then 0
      when :running then rand(10..total_emails/2)
      when :completed then total_emails
      when :failed then rand(5..total_emails/3)
      else rand(0..total_emails)
      end

      detected = (processed * rand(0.1..0.3)).to_i # 10-30% detection rate

      account_status = case status
      when :pending then 'pending'
      when :running then [ 'processing', 'completed' ].sample
      when :completed then 'completed'
      when :failed then [ 'failed', 'completed' ].sample
      else 'processing'
      end

      create(:sync_session_account,
        sync_session: sync_session,
        email_account: account,
        status: account_status,
        total_emails: total_emails,
        processed_emails: processed,
        detected_expenses: detected,
        error_message: account_status == 'failed' ? 'IMAP connection timeout' : nil
      )
    end

    sync_session.update_progress
    sync_session
  end

  # API testing helpers
  def create_iphone_shortcut_expense_payload(overrides = {})
    defaults = {
      amount: rand(1000..50000),
      description: "iPhone Shortcuts: #{sample_businesses.sample}",
      currency: 'CRC',
      date: Date.current.to_s,
      category: 'General',
      source: 'iPhone Shortcuts',
      metadata: {
        device: 'iPhone',
        shortcut_version: '1.0',
        location: 'San José, Costa Rica'
      }
    }

    defaults.merge(overrides)
  end

  def create_batch_expense_payload(count: 5)
    {
      expenses: count.times.map do
        create_iphone_shortcut_expense_payload(
          amount: rand(1000..20000),
          description: "Batch expense: #{sample_businesses.sample}"
        )
      end
    }
  end

  # Performance testing data
  def create_large_dataset_for_performance_testing
    # Create accounts
    banks = [ 'BAC', 'BCR', 'BNCR', 'SCOTIABANK', 'POPULAR' ]
    accounts = banks.map do |bank|
      create(:email_account, bank_name: bank, email: "test@#{bank.downcase}.cr")
    end

    # Create categories
    categories = [
      'Alimentación', 'Transporte', 'Entretenimiento',
      'Compras', 'Servicios', 'Salud', 'Educación'
    ].map { |name| create(:category, name: name) }

    # Create historical expenses (last 6 months)
    expenses = []
    accounts.each do |account|
      6.times do |month_offset|
        month = month_offset.months.ago.beginning_of_month
        expenses.concat(create_monthly_expenses(account: account, month: month, count: rand(30..100)))
      end
    end

    {
      accounts: accounts,
      categories: categories,
      expenses: expenses,
      summary: {
        total_accounts: accounts.count,
        total_categories: categories.count,
        total_expenses: expenses.count,
        date_range: "#{6.months.ago.strftime('%b %Y')} - #{Date.current.strftime('%b %Y')}"
      }
    }
  end

  # Error scenario helpers
  def create_problematic_email_data
    {
      malformed_amounts: [
        "Compra realizada por $1,000.XX en TIENDA", # Invalid decimal
        "Pago de INVALID_AMOUNT en SERVICIO",        # Non-numeric amount
        "Transacción por -₡5,000.00"                # Negative amount (unusual)
      ],
      missing_data: [
        "Compra realizada en TIENDA el 15/01/2024",  # Missing amount
        "Pago por ₡10,000.00",                       # Missing merchant
        "Transacción aprobada"                       # Missing amount and merchant
      ],
      edge_cases: [
        "Compra realizada por ₡0.01 en TEST",        # Minimal amount
        "Pago de ₡999,999,999.99 en LARGE_PURCHASE", # Very large amount
        "Compra realizada por $0.00 en FREE_ITEM"   # Zero amount
      ],
      encoding_issues: [
        "Compra en CAFÉ™ por ₡5,000",               # Special characters
        "Pago en NIÑO'S STORE",                     # Apostrophes
        "Transacción: JOSÉ'S CAFÉ & RESTAURANT"    # Mixed characters
      ]
    }
  end

  # Concurrency testing helpers
  def create_concurrent_test_scenario(user_count: 5, operations_per_user: 10)
    users = user_count.times.map do |i|
      {
        api_token: create(:api_token, name: "Test User #{i + 1}"),
        email_account: create(:email_account, email: "user#{i + 1}@example.com"),
        operations: operations_per_user.times.map do
          create_iphone_shortcut_expense_payload(
            amount: rand(1000..25000),
            description: "Concurrent test #{i + 1}"
          )
        end
      }
    end

    {
      users: users,
      total_operations: user_count * operations_per_user,
      expected_expenses: user_count * operations_per_user
    }
  end

  private

  def format_amount(amount, currency)
    if currency == 'USD'
      sprintf("%.2f", amount)
    else
      amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end

  def generate_realistic_description(bank_name, amount, currency)
    businesses = sample_businesses
    business = businesses.sample
    symbol = currency == 'USD' ? '$' : '₡'
    formatted_amount = format_amount(amount, currency)
    date_str = rand(30.days).seconds.ago.strftime('%d/%m/%Y')

    case bank_name
    when 'BAC'
      "Compra realizada por #{symbol}#{formatted_amount} en #{business} el #{date_str}"
    when 'BCR'
      "BCR: Transaccion #{business} #{symbol}#{formatted_amount} #{date_str}"
    when 'BNCR'
      "BNCR Aviso: #{business} #{symbol}#{formatted_amount}"
    else
      "Pago de #{symbol}#{formatted_amount} en #{business}"
    end
  end
end

# Include test data helpers in relevant specs
RSpec.configure do |config|
  config.include TestDataHelpers

  # Provide shortcuts for common data creation
  config.before(:suite) do
    # Create some default test data that's commonly needed
    unless Rails.env.test?
      raise "TestDataHelpers should only be used in test environment"
    end
  end
end
