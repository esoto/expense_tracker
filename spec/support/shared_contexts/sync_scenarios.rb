# Shared Contexts for Common Sync Testing Scenarios
# Provides reusable test setups for complex sync operations

RSpec.shared_context "with email accounts setup" do
  let!(:bac_account) do
    create(:email_account,
           bank_name: 'BAC',
           email: 'notificaciones@bac.net',
           provider: 'gmail',
           active: true)
  end

  let!(:bcr_account) do
    create(:email_account,
           bank_name: 'BCR',
           email: 'avisos@bcr.fi.cr',
           provider: 'gmail',
           active: true)
  end

  let!(:inactive_account) do
    create(:email_account,
           bank_name: 'BNCR',
           email: 'info@bncr.fi.cr',
           provider: 'gmail',
           active: false)
  end

  let(:active_accounts) { [ bac_account, bcr_account ] }
  let(:all_accounts) { [ bac_account, bcr_account, inactive_account ] }
end

RSpec.shared_context "with expense categories" do
  let!(:food_category) { create(:category, name: 'Alimentación', color: '#4ade80') }
  let!(:transport_category) { create(:category, name: 'Transporte', color: '#3b82f6') }
  let!(:entertainment_category) { create(:category, name: 'Entretenimiento', color: '#a855f7') }
  let!(:shopping_category) { create(:category, name: 'Compras', color: '#f59e0b') }
  let!(:services_category) { create(:category, name: 'Servicios', color: '#06b6d4') }
  let!(:general_category) { create(:category, name: 'General', color: '#6b7280') }

  let(:expense_categories) do
    [ food_category, transport_category, entertainment_category,
     shopping_category, services_category, general_category ]
  end
end

RSpec.shared_context "with realistic expense data" do
  include_context "with email accounts setup"
  include_context "with expense categories"

  let!(:existing_expenses) do
    expenses = []

    # Create 3 months of historical expenses
    (90.days.ago.to_date..Date.current).each do |date|
      active_accounts.each do |account|
        # Random number of expenses per day (0-3)
        rand(0..4).times do
          amount = case rand(1..10)
          when 1..4 then rand(1000..5000)    # Small expenses (₡1k-5k)
          when 5..7 then rand(5000..15000)   # Medium expenses (₡5k-15k)
          when 8..9 then rand(15000..50000)  # Large expenses (₡15k-50k)
          else rand(50000..200000)           # Very large expenses (₡50k-200k)
          end

          currency = account.bank_name == 'BAC' && rand < 0.2 ? 'USD' : 'CRC'
          if currency == 'USD'
            amount = (amount / 500.0).round(2) # Rough CRC to USD conversion
          end

          expense = create(:expense,
            email_account: account,
            category: expense_categories.sample,
            amount: amount,
            currency: currency,
            description: generate_realistic_description(account.bank_name, amount, currency),
            created_at: date + rand(24).hours,
            parsed_at: date + rand(24).hours
          )
          expenses << expense
        end
      end
    end

    expenses
  end

  def generate_realistic_description(bank_name, amount, currency)
    businesses = {
      'food' => [ 'AutoMercado', 'Mas x Menos', 'Fresh Market', 'Walmart', 'PriceSmart' ],
      'gas' => [ 'Delta', 'Uno', 'Servicentro' ],
      'restaurant' => [ 'McDonalds', 'Pizza Hut', 'Taco Bell', 'Subway', 'KFC' ],
      'pharmacy' => [ 'Fischel', 'Farmacia Sucre', 'Farmacia Chavarria' ],
      'shopping' => [ 'Plaza Real', 'City Mall', 'Multiplaza', 'Amazon' ],
      'services' => [ 'ICE', 'Kölbi', 'Netflix', 'Spotify' ]
    }

    category = case amount
    when 0..3000 then [ 'food', 'pharmacy' ].sample
    when 3000..10000 then [ 'restaurant', 'gas', 'pharmacy' ].sample
    when 10000..30000 then [ 'food', 'shopping' ].sample
    else [ 'shopping', 'services' ].sample
    end

    business = businesses[category].sample
    symbol = currency == 'USD' ? '$' : '₡'
    formatted_amount = currency == 'USD' ? "#{symbol}#{amount}" : "#{symbol}#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

    date_str = (Date.current - rand(90)).strftime('%d/%m/%Y')

    case bank_name
    when 'BAC'
      "Compra realizada por #{formatted_amount} en #{business} el #{date_str}"
    when 'BCR'
      "Transaccion #{business} #{formatted_amount} #{date_str}"
    else
      "Pago de #{formatted_amount} en #{business}"
    end
  end
end

RSpec.shared_context "with running sync session" do
  include_context "with email accounts setup"

  let!(:sync_session) { create(:sync_session, :running, started_at: 2.minutes.ago) }
  let!(:sync_accounts) do
    active_accounts.map do |account|
      create(:sync_session_account,
             sync_session: sync_session,
             email_account: account,
             status: 'processing',
             total_emails: rand(50..200),
             processed_emails: rand(10..50),
             detected_expenses: rand(5..25))
    end
  end

  before do
    # Update sync session totals based on accounts
    sync_session.update_progress
  end
end

RSpec.shared_context "with completed sync session" do
  include_context "with email accounts setup"

  let!(:sync_session) do
    create(:sync_session, :completed,
           started_at: 10.minutes.ago,
           completed_at: 2.minutes.ago)
  end

  let!(:sync_accounts) do
    active_accounts.map do |account|
      total = rand(100..300)
      create(:sync_session_account,
             sync_session: sync_session,
             email_account: account,
             status: 'completed',
             total_emails: total,
             processed_emails: total,
             detected_expenses: rand(20..60))
    end
  end

  before do
    sync_session.update_progress
  end
end

RSpec.shared_context "with failed sync session" do
  include_context "with email accounts setup"

  let!(:sync_session) do
    create(:sync_session, :failed,
           started_at: 15.minutes.ago,
           completed_at: 5.minutes.ago,
           error_details: "IMAP connection timeout")
  end

  let!(:sync_accounts) do
    accounts_with_status = [
      { account: bac_account, status: 'failed', error: 'IMAP timeout' },
      { account: bcr_account, status: 'completed', error: nil }
    ]

    accounts_with_status.map do |config|
      total = rand(50..150)
      processed = config[:status] == 'completed' ? total : rand(10..30)

      create(:sync_session_account,
             sync_session: sync_session,
             email_account: config[:account],
             status: config[:status],
             total_emails: total,
             processed_emails: processed,
             detected_expenses: config[:status] == 'completed' ? rand(10..30) : 0,
             error_message: config[:error])
    end
  end

  before do
    sync_session.update_progress
  end
end

RSpec.shared_context "with mocked IMAP responses" do
  let(:sample_bac_emails) do
    [
      "Estimado Cliente, Compra realizada por ₡15,750.50 en AUTOMERCADO #123 el 15/01/2024 a las 14:30. Su saldo disponible es ₡450,200.75. BAC",
      "Compra realizada por $45.25 USD en AMAZON.COM el 16/01/2024. Tipo de cambio: ₡520.50. BAC San José",
      "Retiro en ATM por ₡50,000.00 en BAC MULTIPLAZA el 17/01/2024 a las 09:15. Comisión: ₡0.00",
      "Pago de servicios por ₡28,450.00 a ICE-KOLBI el 18/01/2024. Referencia: 789456123",
      "Transferencia realizada por ₡125,000.00 a JUAN PEREZ el 19/01/2024. Comisión: ₡500.00"
    ]
  end

  let(:sample_bcr_emails) do
    [
      "BCR Aviso: Compra POS ₡8,950.00 MAS X MENOS #45 15/01/2024 10:25 Aprobada. Saldo: ₡234,100.50",
      "Transaccion Aprobada: DELTA GASOLINERA ₡35,000.00 16/01/2024 Tarjeta: ****1234",
      "BCR: Pago de Marchamo ₡89,750.00 COSEVI 17/01/2024. Referencia: MC789654",
      "Compra Internacional: NETFLIX.COM $15.99 USD 18/01/2024 T.C: ₡525.30",
      "ATM Retiro: ₡100,000.00 BCR ESCAZU 19/01/2024 08:45. Disponible: ₡189,300.25"
    ]
  end

  let(:mixed_emails) do
    [
      *sample_bac_emails.sample(3),
      *sample_bcr_emails.sample(3),
      "This is not a transaction email - just a promotional message",
      "BCR: Su estado de cuenta está disponible en línea",
      "Mantenimiento programado en nuestros sistemas - BAC"
    ]
  end

  before do
    allow_any_instance_of(EmailProcessing::Fetcher).to receive(:fetch_new_emails).and_return({
      success: true,
      expenses_created: 5,
      total_emails_processed: 10,
      errors: []
    })
  end
end

RSpec.shared_context "with ActionCable test setup" do
  before do
    # Clear any existing ActionCable connections and broadcasts
    ActionCable.server.pubsub.clear if ActionCable.server.pubsub.respond_to?(:clear)

    # Set up test adapter if not already configured
    ActionCable.server.config.cable = { adapter: 'test' }
  end

  after do
    # Clean up ActionCable state
    ActionCable.server.pubsub.clear if ActionCable.server.pubsub.respond_to?(:clear)
  end
end

RSpec.shared_context "with performance monitoring" do
  let(:performance_thresholds) do
    {
      database_queries: 10,
      execution_time: 5.seconds,
      memory_usage: 50.megabytes
    }
  end

  before do
    @initial_memory = (GC.stat[:heap_allocated_pages] * GC.stat[:heap_allocated_slots] * 40.0) / (1024 * 1024)
    @query_count = 0

    @query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do
      @query_count += 1
    end
  end

  after do
    ActiveSupport::Notifications.unsubscribe(@query_subscriber) if @query_subscriber

    final_memory = (GC.stat[:heap_allocated_pages] * GC.stat[:heap_allocated_slots] * 40.0) / (1024 * 1024)
    memory_growth = final_memory - @initial_memory

    # Only check performance in tagged specs
    if example.metadata[:performance]
      expect(@query_count).to be <= performance_thresholds[:database_queries],
        "Expected at most #{performance_thresholds[:database_queries]} queries, but executed #{@query_count}"

      expect(memory_growth).to be < (performance_thresholds[:memory_usage] / 1.megabyte),
        "Memory grew by #{memory_growth}MB, expected under #{performance_thresholds[:memory_usage] / 1.megabyte}MB"
    end
  end
end

RSpec.shared_context "with time manipulation" do
  around do |example|
    travel_to Time.zone.parse('2024-01-15 14:30:00') do
      example.run
    end
  end
end

# Helper method to easily include multiple contexts
def with_full_sync_setup
  include_context "with email accounts setup"
  include_context "with expense categories"
  include_context "with mocked IMAP responses"
  include_context "with ActionCable test setup"
end

def with_performance_testing
  include_context "with performance monitoring"
  include_context "with realistic expense data"
end
