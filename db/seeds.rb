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
