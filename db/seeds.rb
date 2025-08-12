# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding initial data..."

# Create expense categories
puts "Creating expense categories..."

root_categories = [
  { name: "Alimentación", description: "Comida, restaurantes, supermercados", color: "#FF6B6B" },
  { name: "Transporte", description: "Gasolina, Uber, taxis, transporte público", color: "#4ECDC4" },
  { name: "Servicios", description: "Electricidad, agua, teléfono, internet", color: "#45B7D1" },
  { name: "Entretenimiento", description: "Cine, teatro, eventos, diversión", color: "#96CEB4" },
  { name: "Salud", description: "Medicina, doctor, hospital, farmacia", color: "#FFEAA7" },
  { name: "Compras", description: "Ropa, electrónicos, artículos personales", color: "#DDA0DD" },
  { name: "Educación", description: "Cursos, libros, capacitación", color: "#98D8C8" },
  { name: "Hogar", description: "Artículos para el hogar, mantenimiento", color: "#F7DC6F" },
  { name: "Sin Categoría", description: "Gastos sin categorizar", color: "#BDC3C7" }
]

root_categories.each do |category_data|
  category = Category.find_or_create_by!(name: category_data[:name]) do |cat|
    cat.description = category_data[:description]
    cat.color = category_data[:color]
  end
  puts "  ✓ #{category.name}"
end

# Create subcategories
puts "Creating subcategories..."

subcategories = [
  { parent: "Alimentación", name: "Restaurantes", description: "Comidas en restaurantes" },
  { parent: "Alimentación", name: "Supermercado", description: "Compras de comestibles" },
  { parent: "Alimentación", name: "Cafetería", description: "Café, desayunos, snacks" },

  { parent: "Transporte", name: "Gasolina", description: "Combustible para vehículo" },
  { parent: "Transporte", name: "Uber/Taxi", description: "Servicios de transporte" },
  { parent: "Transporte", name: "Autobús", description: "Transporte público" },

  { parent: "Servicios", name: "Electricidad", description: "Factura de electricidad" },
  { parent: "Servicios", name: "Agua", description: "Factura de agua" },
  { parent: "Servicios", name: "Internet", description: "Servicio de internet" },
  { parent: "Servicios", name: "Teléfono", description: "Servicio telefónico" },

  { parent: "Compras", name: "Ropa", description: "Vestimenta y accesorios" },
  { parent: "Compras", name: "Electrónicos", description: "Dispositivos electrónicos" },
  { parent: "Compras", name: "Hogar", description: "Artículos para el hogar" }
]

subcategories.each do |subcat_data|
  parent = Category.find_by!(name: subcat_data[:parent])
  subcategory = Category.find_or_create_by!(name: subcat_data[:name]) do |cat|
    cat.parent = parent
    cat.description = subcat_data[:description]
  end
  puts "  ✓ #{parent.name} > #{subcategory.name}"
end

# Create API tokens
puts "Creating API tokens..."

api_tokens = [
  { name: "iPhone Shortcuts", expires_at: 1.year.from_now },
  { name: "Development Testing", expires_at: 6.months.from_now }
]

created_tokens = []
api_tokens.each do |token_data|
  token = ApiToken.find_or_create_by!(name: token_data[:name]) do |t|
    t.expires_at = token_data[:expires_at]
    t.active = true
  end

  if token.token.present?
    created_tokens << { name: token.name, token: token.token }
    puts "  ✓ #{token.name}: #{token.token}"
  else
    puts "  ✓ #{token.name}: (already exists)"
  end
end

# Create Costa Rican bank parsing rules (focused on BAC based on voucher)
puts "Creating Costa Rican bank parsing rules..."

parsing_rules = [
  {
    bank_name: "BAC",
    email_pattern: "(?:transacci[oó]n|notificaci[oó]n).*(?:BAC|PTA)",
    amount_pattern: "(?:Monto)[: ]*(?:USD|CRC)[: ]*([\\d,]+\\.\\d{2})",
    date_pattern: "Fecha:\\s*(.+?)(?=\\n|$)",
    merchant_pattern: "(?:Comercio)[: ]*([A-Z0-9 .]+?)(?: *Ciudad| *Fecha| *VISA| *MASTER)",
    description_pattern: "(?:Tipo de Transacci[oó]n)[:\\s]*([A-Z]+)"
  },
  {
    bank_name: "BCR",
    email_pattern: "(?:transacci[oó]n|compra|pago|cargo).*BCR",
    amount_pattern: "(?:₡|colones?|CRC)[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)",
    date_pattern: "(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
    merchant_pattern: "(?:comercio|merchant|establecimiento)[:\\s]+(.*?)(?:\\n|$)",
    description_pattern: "(?:descripcion|concepto)[:\\s]+(.*?)(?:\\n|$)"
  },
  {
    bank_name: "Scotiabank",
    email_pattern: "(?:transacci[oó]n|transaction).*Scotia",
    amount_pattern: "(?:₡|CRC)[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)",
    date_pattern: "(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
    merchant_pattern: "(?:merchant|comercio)[:\\s]+(.*?)(?:\\n|$)",
    description_pattern: "(?:description|descripcion)[:\\s]+(.*?)(?:\\n|$)"
  },
  {
    bank_name: "Banco Nacional",
    email_pattern: "(?:notificaci[oó]n|transacci[oó]n).*(?:Banco Nacional|BNCR)",
    amount_pattern: "(?:₡|colones)[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)",
    date_pattern: "(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})",
    merchant_pattern: "(?:establecimiento|comercio)[:\\s]+(.*?)(?:\\n|$)",
    description_pattern: "(?:detalle|concepto)[:\\s]+(.*?)(?:\\n|$)"
  }
]

parsing_rules.each do |rule_data|
  rule = ParsingRule.find_or_create_by!(bank_name: rule_data[:bank_name]) do |r|
    r.email_pattern = rule_data[:email_pattern]
    r.amount_pattern = rule_data[:amount_pattern]
    r.date_pattern = rule_data[:date_pattern]
    r.merchant_pattern = rule_data[:merchant_pattern]
    r.description_pattern = rule_data[:description_pattern]
    r.active = true
  end
  puts "  ✓ #{rule.bank_name}"
end

puts ""
puts "✅ Seed data created successfully!"
puts ""

if created_tokens.any?
  puts "📱 NEW API Tokens for iPhone Shortcuts:"
  created_tokens.each do |token_info|
    puts "  • #{token_info[:name]}: #{token_info[:token]}"
  end
  puts "  ⚠️  Save these tokens securely - they won't be shown again!"
  puts ""
end

puts "🏦 Bank parsing rules created for:"
ParsingRule.active.pluck(:bank_name).each do |bank|
  puts "  • #{bank}"
end
puts ""
puts "📂 Categories created:"
Category.root_categories.each do |category|
  puts "  • #{category.name} (#{category.children.count} subcategories)"
end
puts ""
puts "🚀 Ready to use! API endpoints:"
puts "  • POST /api/webhooks/process_emails"
puts "  • POST /api/webhooks/add_expense"
puts "  • GET /api/webhooks/recent_expenses"
puts "  • GET /api/webhooks/expense_summary"

# Load categorization patterns if the file exists
categorization_patterns_file = Rails.root.join("db/seeds/categorization_patterns.rb")
if File.exist?(categorization_patterns_file)
  puts ""
  load categorization_patterns_file
end

# Create sync performance metrics data
puts ""
puts "📊 Creating sync performance metrics..."

if SyncSession.any? && EmailAccount.any?
  # Use existing sessions and accounts for metrics
  email_accounts = EmailAccount.active.to_a

  # Create metrics for the last 30 days
  30.times do |days_ago|
    date = days_ago.days.ago

    # Create 2-5 sync sessions per day
    rand(2..5).times do |session_num|
      session_start = date.beginning_of_day + rand(0..23).hours + rand(0..59).minutes

      # Create or find a sync session for this time
      sync_session = SyncSession.create!(
        status: 'completed',
        started_at: session_start,
        completed_at: session_start + rand(5..30).minutes,
        total_emails: rand(50..500),
        processed_emails: rand(45..495),
        detected_expenses: rand(0..20),
        errors_count: rand(0..3),
        sync_type: [ 'manual', 'scheduled' ].sample
      )

      # Create session-level metric
      SyncMetric.create!(
        sync_session: sync_session,
        metric_type: 'session_overall',
        success: [ true, true, true, false ].sample, # 75% success rate
        duration: rand(5000..60000), # 5-60 seconds
        emails_processed: sync_session.processed_emails,
        started_at: session_start,
        completed_at: sync_session.completed_at
      )

      # Create metrics for each email account
      email_accounts.sample(rand(1..email_accounts.size)).each do |account|
        account_start = session_start + rand(0..5).seconds

        # Email fetch metric
        fetch_duration = rand(1000..5000) # 1-5 seconds
        SyncMetric.create!(
          sync_session: sync_session,
          email_account: account,
          metric_type: 'email_fetch',
          success: [ true, true, true, true, false ].sample, # 80% success
          duration: fetch_duration,
          emails_processed: rand(10..100),
          started_at: account_start,
          completed_at: account_start + fetch_duration.milliseconds,
          error_type: [ nil, nil, nil, 'ImapConnectionError' ].sample,
          error_message: [ nil, nil, nil, 'Connection timeout' ].sample
        )

        # Email parse metrics (multiple per account)
        rand(5..20).times do |i|
          parse_start = account_start + (fetch_duration + (i * 100)).milliseconds
          parse_duration = rand(50..500) # 50-500ms

          SyncMetric.create!(
            sync_session: sync_session,
            email_account: account,
            metric_type: 'email_parse',
            success: [ true, true, true, true, true, false ].sample, # 83% success
            duration: parse_duration,
            emails_processed: 1,
            started_at: parse_start,
            completed_at: parse_start + parse_duration.milliseconds
          )
        end

        # Expense detection metrics
        rand(0..5).times do |i|
          detect_start = account_start + rand(2000..10000).milliseconds
          detect_duration = rand(100..1000) # 100ms-1s

          SyncMetric.create!(
            sync_session: sync_session,
            email_account: account,
            metric_type: 'expense_detection',
            success: true,
            duration: detect_duration,
            emails_processed: 1,
            started_at: detect_start,
            completed_at: detect_start + detect_duration.milliseconds,
            metadata: {
              amount: rand(1000..50000),
              merchant: [ 'Automercado', 'Walmart', 'EPA', 'Mas x Menos' ].sample,
              category: [ 'Alimentación', 'Compras', 'Hogar' ].sample
            }
          )
        end

        # Conflict detection metrics
        if rand < 0.3 # 30% chance of conflicts
          conflict_start = account_start + rand(3000..15000).milliseconds
          conflict_duration = rand(200..2000) # 200ms-2s

          SyncMetric.create!(
            sync_session: sync_session,
            email_account: account,
            metric_type: 'conflict_detection',
            success: true,
            duration: conflict_duration,
            emails_processed: 0,
            started_at: conflict_start,
            completed_at: conflict_start + conflict_duration.milliseconds,
            metadata: {
              conflicts_found: rand(1..3),
              similarity_score: rand(70..95)
            }
          )
        end

        # Database write metrics
        rand(1..10).times do |i|
          write_start = account_start + rand(1000..20000).milliseconds
          write_duration = rand(10..100) # 10-100ms

          SyncMetric.create!(
            sync_session: sync_session,
            email_account: account,
            metric_type: 'database_write',
            success: [ true, true, true, true, true, true, false ].sample, # 86% success
            duration: write_duration,
            emails_processed: 0,
            started_at: write_start,
            completed_at: write_start + write_duration.milliseconds
          )
        end

        # Broadcast metrics
        rand(3..8).times do |i|
          broadcast_start = account_start + rand(1000..25000).milliseconds
          broadcast_duration = rand(5..50) # 5-50ms

          SyncMetric.create!(
            sync_session: sync_session,
            email_account: account,
            metric_type: 'broadcast',
            success: [ true, true, true, true, true, true, true, false ].sample, # 87.5% success
            duration: broadcast_duration,
            emails_processed: 0,
            started_at: broadcast_start,
            completed_at: broadcast_start + broadcast_duration.milliseconds,
            metadata: {
              channel: [ 'SyncStatusChannel', 'DashboardChannel' ].sample,
              event: [ 'progress_update', 'expense_detected', 'conflict_detected' ].sample
            }
          )
        end

        # Account sync summary metric
        account_sync_duration = rand(10000..60000) # 10-60 seconds
        SyncMetric.create!(
          sync_session: sync_session,
          email_account: account,
          metric_type: 'account_sync',
          success: [ true, true, true, false ].sample, # 75% success
          duration: account_sync_duration,
          emails_processed: rand(10..100),
          started_at: account_start,
          completed_at: account_start + account_sync_duration.milliseconds
        )
      end
    end
  end

  puts "  ✓ Created #{SyncMetric.count} performance metrics"
  puts "  ✓ Metrics span the last 30 days"
  puts "  ✓ Includes all metric types: #{SyncMetric::METRIC_TYPES.values.join(', ')}"
else
  puts "  ⚠️  Skipping metrics creation - no sync sessions or email accounts found"
  puts "  ℹ️  Run sync operations first to generate real metrics"
end

# Create admin user for development
puts ""
puts "👤 Creating admin user..."

admin_email = "admin@expense-tracker.com"
admin_password = "AdminPassword123!"

admin_user = AdminUser.find_or_create_by!(email: admin_email) do |user|
  user.name = "System Administrator"
  user.password = admin_password
  user.role = "super_admin"
end

if admin_user.persisted?
  puts "  ✓ Admin user created: #{admin_email}"
  puts "  🔑 Password: #{admin_password}"
  puts "  ⚠️  Change this password in production!"
else
  puts "  ✓ Admin user already exists: #{admin_email}"
end
