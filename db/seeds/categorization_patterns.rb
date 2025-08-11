# frozen_string_literal: true

# Comprehensive seed data for categorization patterns
# This file creates 50+ diverse patterns across all categories with realistic data

puts "🔄 Seeding categorization patterns..."

# Helper method to create pattern with metadata
def create_pattern(category_name, pattern_data)
  category = Category.find_by(name: category_name)
  return unless category

  pattern = CategorizationPattern.find_or_initialize_by(
    category: category,
    pattern_type: pattern_data[:type],
    pattern_value: pattern_data[:value]
  )

  pattern.assign_attributes(
    confidence_weight: pattern_data[:confidence] || 1.0,
    active: pattern_data[:active] != false,
    user_created: pattern_data[:user_created] || false,
    usage_count: pattern_data[:usage_count] || 0,
    success_count: pattern_data[:success_count] || 0,
    metadata: pattern_data[:metadata] || {}
  )

  # Calculate success rate
  if pattern.usage_count > 0
    pattern.success_rate = pattern.success_count.to_f / pattern.usage_count
  end

  pattern.save!
  pattern
rescue => e
  puts "  ⚠️  Error creating pattern for #{category_name}: #{e.message}"
end

# Food & Dining Patterns (Alimentación)
food_patterns = [
  # Merchant patterns - restaurants
  { type: "merchant", value: "mcdonalds", confidence: 4.5, usage_count: 150, success_count: 142 },
  { type: "merchant", value: "burger king", confidence: 4.5, usage_count: 89, success_count: 85 },
  { type: "merchant", value: "pizza hut", confidence: 4.5, usage_count: 67, success_count: 64 },
  { type: "merchant", value: "subway", confidence: 4.0, usage_count: 45, success_count: 42 },
  { type: "merchant", value: "starbucks", confidence: 4.0, usage_count: 234, success_count: 220 },
  { type: "merchant", value: "kfc", confidence: 4.0, usage_count: 56, success_count: 53 },
  { type: "merchant", value: "taco bell", confidence: 4.0, usage_count: 38, success_count: 36 },
  { type: "merchant", value: "restaurante", confidence: 3.0, usage_count: 89, success_count: 75 },

  # Keyword patterns for food
  { type: "keyword", value: "cafe", confidence: 2.5, usage_count: 178, success_count: 142 },
  { type: "keyword", value: "coffee", confidence: 2.5, usage_count: 156, success_count: 130 },
  { type: "keyword", value: "almuerzo", confidence: 3.0, usage_count: 67, success_count: 58 },
  { type: "keyword", value: "desayuno", confidence: 3.0, usage_count: 45, success_count: 40 },
  { type: "keyword", value: "cena", confidence: 3.0, usage_count: 38, success_count: 34 },
  { type: "keyword", value: "comida", confidence: 2.0, usage_count: 92, success_count: 69 },

  # Time patterns for meals
  { type: "time", value: "06:00-10:00", confidence: 1.5, usage_count: 89, success_count: 71 },
  { type: "time", value: "12:00-14:00", confidence: 1.5, usage_count: 134, success_count: 107 },
  { type: "time", value: "18:00-21:00", confidence: 1.5, usage_count: 98, success_count: 78 },

  # Amount ranges for meals
  { type: "amount_range", value: "5.00-15.00", confidence: 1.0, usage_count: 234, success_count: 164 },
  { type: "amount_range", value: "15.00-30.00", confidence: 0.8, usage_count: 156, success_count: 101 }
]

# Groceries Patterns (Supermercado)
grocery_patterns = [
  # Merchant patterns - supermarkets
  { type: "merchant", value: "walmart", confidence: 4.8, usage_count: 234, success_count: 226 },
  { type: "merchant", value: "automercado", confidence: 4.8, usage_count: 189, success_count: 182 },
  { type: "merchant", value: "mas x menos", confidence: 4.5, usage_count: 156, success_count: 148 },
  { type: "merchant", value: "pali", confidence: 4.5, usage_count: 134, success_count: 127 },
  { type: "merchant", value: "fresh market", confidence: 4.0, usage_count: 67, success_count: 62 },
  { type: "merchant", value: "pricesmart", confidence: 4.5, usage_count: 89, success_count: 85 },

  # Keyword patterns
  { type: "keyword", value: "supermercado", confidence: 3.5, usage_count: 298, success_count: 253 },
  { type: "keyword", value: "mercado", confidence: 2.5, usage_count: 145, success_count: 109 },
  { type: "keyword", value: "groceries", confidence: 3.0, usage_count: 78, success_count: 66 },

  # Amount ranges for groceries
  { type: "amount_range", value: "30.00-100.00", confidence: 1.2, usage_count: 345, success_count: 276 },
  { type: "amount_range", value: "100.00-300.00", confidence: 1.5, usage_count: 234, success_count: 199 }
]

# Transportation Patterns (Transporte)
transport_patterns = [
  # Merchant patterns - gas stations
  { type: "merchant", value: "delta", confidence: 4.5, usage_count: 145, success_count: 138 },
  { type: "merchant", value: "uno", confidence: 4.5, usage_count: 123, success_count: 117 },
  { type: "merchant", value: "gulf", confidence: 4.0, usage_count: 89, success_count: 83 },

  # Ride sharing
  { type: "merchant", value: "uber", confidence: 4.8, usage_count: 567, success_count: 545 },
  { type: "merchant", value: "didi", confidence: 4.5, usage_count: 234, success_count: 220 },
  { type: "merchant", value: "indriver", confidence: 4.0, usage_count: 123, success_count: 111 },

  # Keywords
  { type: "keyword", value: "gasolina", confidence: 3.5, usage_count: 234, success_count: 199 },
  { type: "keyword", value: "combustible", confidence: 3.5, usage_count: 189, success_count: 161 },
  { type: "keyword", value: "taxi", confidence: 3.0, usage_count: 98, success_count: 78 },
  { type: "keyword", value: "peaje", confidence: 4.0, usage_count: 67, success_count: 64 },

  # Regex patterns
  { type: "regex", value: "\\b(gas|fuel|diesel)\\b", confidence: 2.5, usage_count: 145, success_count: 116 },

  # Amount ranges for gas
  { type: "amount_range", value: "20.00-50.00", confidence: 1.0, usage_count: 234, success_count: 164 }
]

# Utilities Patterns (Servicios)
utilities_patterns = [
  # Merchant patterns - utilities
  { type: "merchant", value: "ice", confidence: 4.8, usage_count: 234, success_count: 229 },
  { type: "merchant", value: "cnfl", confidence: 4.8, usage_count: 189, success_count: 185 },
  { type: "merchant", value: "aya", confidence: 4.8, usage_count: 156, success_count: 152 },
  { type: "merchant", value: "kolbi", confidence: 4.5, usage_count: 234, success_count: 222 },
  { type: "merchant", value: "claro", confidence: 4.5, usage_count: 145, success_count: 138 },
  { type: "merchant", value: "movistar", confidence: 4.5, usage_count: 123, success_count: 117 },
  { type: "merchant", value: "tigo", confidence: 4.5, usage_count: 189, success_count: 180 },
  { type: "merchant", value: "telecable", confidence: 4.5, usage_count: 89, success_count: 85 },

  # Keywords
  { type: "keyword", value: "electricidad", confidence: 3.5, usage_count: 234, success_count: 211 },
  { type: "keyword", value: "agua", confidence: 3.0, usage_count: 189, success_count: 151 },
  { type: "keyword", value: "internet", confidence: 3.5, usage_count: 167, success_count: 142 },
  { type: "keyword", value: "telefono", confidence: 3.0, usage_count: 145, success_count: 116 },

  # Description patterns
  { type: "description", value: "pago de servicio", confidence: 3.0, usage_count: 345, success_count: 293 },
  { type: "description", value: "factura", confidence: 2.0, usage_count: 234, success_count: 164 },

  # Amount ranges for utilities
  { type: "amount_range", value: "30.00-80.00", confidence: 1.0, usage_count: 456, success_count: 319 },
  { type: "amount_range", value: "80.00-150.00", confidence: 0.8, usage_count: 234, success_count: 164 }
]

# Entertainment Patterns (Entretenimiento)
entertainment_patterns = [
  # Merchant patterns
  { type: "merchant", value: "netflix", confidence: 4.8, usage_count: 345, success_count: 338 },
  { type: "merchant", value: "spotify", confidence: 4.8, usage_count: 289, success_count: 283 },
  { type: "merchant", value: "disney", confidence: 4.5, usage_count: 167, success_count: 159 },
  { type: "merchant", value: "hbo", confidence: 4.5, usage_count: 145, success_count: 138 },
  { type: "merchant", value: "cinepolis", confidence: 4.5, usage_count: 234, success_count: 222 },
  { type: "merchant", value: "ccm cinemas", confidence: 4.5, usage_count: 189, success_count: 180 },

  # Keywords
  { type: "keyword", value: "cine", confidence: 3.5, usage_count: 234, success_count: 199 },
  { type: "keyword", value: "streaming", confidence: 3.0, usage_count: 167, success_count: 134 },
  { type: "keyword", value: "teatro", confidence: 3.5, usage_count: 45, success_count: 41 },
  { type: "keyword", value: "concierto", confidence: 3.5, usage_count: 67, success_count: 60 },

  # Time patterns for entertainment
  { type: "time", value: "weekend", confidence: 1.5, usage_count: 345, success_count: 259 },
  { type: "time", value: "19:00-23:00", confidence: 1.2, usage_count: 234, success_count: 164 },

  # Amount ranges
  { type: "amount_range", value: "5.00-20.00", confidence: 1.0, usage_count: 456, success_count: 319 }
]

# Shopping Patterns (Compras)
shopping_patterns = [
  # Merchant patterns - stores
  { type: "merchant", value: "amazon", confidence: 4.5, usage_count: 456, success_count: 433 },
  { type: "merchant", value: "ebay", confidence: 4.0, usage_count: 123, success_count: 111 },
  { type: "merchant", value: "zara", confidence: 4.5, usage_count: 189, success_count: 180 },
  { type: "merchant", value: "h&m", confidence: 4.5, usage_count: 167, success_count: 159 },
  { type: "merchant", value: "universal", confidence: 4.0, usage_count: 234, success_count: 211 },
  { type: "merchant", value: "ekono", confidence: 4.0, usage_count: 189, success_count: 170 },

  # Keywords
  { type: "keyword", value: "tienda", confidence: 2.5, usage_count: 345, success_count: 259 },
  { type: "keyword", value: "ropa", confidence: 3.0, usage_count: 234, success_count: 187 },
  { type: "keyword", value: "zapatos", confidence: 3.5, usage_count: 123, success_count: 108 },
  { type: "keyword", value: "electronico", confidence: 3.0, usage_count: 189, success_count: 151 },

  # Regex patterns
  { type: "regex", value: "\\b(shop|store|mall)\\b", confidence: 2.0, usage_count: 234, success_count: 164 },

  # Amount ranges
  { type: "amount_range", value: "50.00-200.00", confidence: 0.8, usage_count: 567, success_count: 397 },
  { type: "amount_range", value: "200.00-500.00", confidence: 0.6, usage_count: 234, success_count: 140 }
]

# Healthcare Patterns (Salud)
healthcare_patterns = [
  # Merchant patterns
  { type: "merchant", value: "farmacia", confidence: 3.5, usage_count: 234, success_count: 199 },
  { type: "merchant", value: "fischel", confidence: 4.5, usage_count: 189, success_count: 180 },
  { type: "merchant", value: "bomba", confidence: 4.0, usage_count: 145, success_count: 131 },
  { type: "merchant", value: "clinica", confidence: 3.5, usage_count: 123, success_count: 104 },
  { type: "merchant", value: "hospital", confidence: 3.5, usage_count: 89, success_count: 76 },

  # Keywords
  { type: "keyword", value: "medicina", confidence: 3.5, usage_count: 234, success_count: 199 },
  { type: "keyword", value: "doctor", confidence: 3.5, usage_count: 167, success_count: 142 },
  { type: "keyword", value: "laboratorio", confidence: 3.5, usage_count: 123, success_count: 108 },
  { type: "keyword", value: "salud", confidence: 2.5, usage_count: 189, success_count: 142 },

  # Description patterns
  { type: "description", value: "consulta medica", confidence: 4.0, usage_count: 145, success_count: 134 },
  { type: "description", value: "examen", confidence: 3.0, usage_count: 89, success_count: 71 },

  # Amount ranges for healthcare
  { type: "amount_range", value: "20.00-100.00", confidence: 0.8, usage_count: 345, success_count: 241 },
  { type: "amount_range", value: "100.00-500.00", confidence: 0.6, usage_count: 167, success_count: 100 }
]

# Education Patterns (Educación)
education_patterns = [
  # Merchant patterns
  { type: "merchant", value: "libreria", confidence: 3.5, usage_count: 123, success_count: 104 },
  { type: "merchant", value: "universal", confidence: 3.0, usage_count: 89, success_count: 67 },
  { type: "merchant", value: "amazon books", confidence: 4.0, usage_count: 67, success_count: 61 },

  # Keywords
  { type: "keyword", value: "libro", confidence: 3.5, usage_count: 145, success_count: 123 },
  { type: "keyword", value: "curso", confidence: 3.5, usage_count: 123, success_count: 108 },
  { type: "keyword", value: "universidad", confidence: 3.5, usage_count: 89, success_count: 78 },
  { type: "keyword", value: "colegio", confidence: 3.5, usage_count: 67, success_count: 60 },

  # Description patterns
  { type: "description", value: "matricula", confidence: 4.0, usage_count: 45, success_count: 43 },
  { type: "description", value: "mensualidad", confidence: 3.5, usage_count: 67, success_count: 60 },

  # Amount ranges
  { type: "amount_range", value: "50.00-300.00", confidence: 0.7, usage_count: 234, success_count: 164 }
]

# Home Patterns (Hogar)
home_patterns = [
  # Merchant patterns
  { type: "merchant", value: "epa", confidence: 4.5, usage_count: 234, success_count: 222 },
  { type: "merchant", value: "construplaza", confidence: 4.5, usage_count: 189, success_count: 180 },
  { type: "merchant", value: "pequeño mundo", confidence: 4.0, usage_count: 145, success_count: 131 },

  # Keywords
  { type: "keyword", value: "ferreteria", confidence: 3.5, usage_count: 189, success_count: 161 },
  { type: "keyword", value: "muebles", confidence: 3.5, usage_count: 123, success_count: 108 },
  { type: "keyword", value: "decoracion", confidence: 3.0, usage_count: 89, success_count: 71 },
  { type: "keyword", value: "jardin", confidence: 3.0, usage_count: 67, success_count: 54 },

  # Description patterns
  { type: "description", value: "mantenimiento", confidence: 2.5, usage_count: 145, success_count: 109 },
  { type: "description", value: "reparacion", confidence: 2.5, usage_count: 123, success_count: 92 },

  # Amount ranges
  { type: "amount_range", value: "20.00-150.00", confidence: 0.8, usage_count: 345, success_count: 241 }
]

# Create all patterns
all_patterns = {
  "Alimentación" => food_patterns,
  "Supermercado" => grocery_patterns,
  "Transporte" => transport_patterns,
  "Servicios" => utilities_patterns,
  "Entretenimiento" => entertainment_patterns,
  "Compras" => shopping_patterns,
  "Salud" => healthcare_patterns,
  "Educación" => education_patterns,
  "Hogar" => home_patterns
}

pattern_count = 0
all_patterns.each do |category_name, patterns|
  puts "  📁 Creating patterns for #{category_name}..."
  patterns.each do |pattern_data|
    if create_pattern(category_name, pattern_data)
      pattern_count += 1
    end
  end
end

# Add some edge case patterns for testing
puts "  🔬 Creating edge case patterns for testing..."

# Create patterns with various success rates
test_patterns = [
  # Very successful pattern
  { category: "Alimentación", type: "merchant", value: "test_high_success",
    confidence: 5.0, usage_count: 1000, success_count: 950 },

  # Failing pattern
  { category: "Transporte", type: "keyword", value: "test_low_success",
    confidence: 1.0, usage_count: 100, success_count: 10 },

  # Unused pattern (old)
  { category: "Servicios", type: "regex", value: "\\btest_unused\\b",
    confidence: 1.0, usage_count: 0, success_count: 0 },

  # Complex regex pattern
  { category: "Compras", type: "regex", value: "\\b(buy|purchase|order)\\s+(\\w+\\s*){1,3}\\b",
    confidence: 2.0, usage_count: 50, success_count: 35 },

  # Negative amount range
  { category: "Sin Categoría", type: "amount_range", value: "-100.00--10.00",
    confidence: 1.5, usage_count: 30, success_count: 25 },

  # Weekend time pattern
  { category: "Entretenimiento", type: "time", value: "weekend",
    confidence: 1.5, usage_count: 200, success_count: 160 },

  # Business hours pattern
  { category: "Servicios", type: "time", value: "09:00-17:00",
    confidence: 1.2, usage_count: 150, success_count: 120 }
]

test_patterns.each do |pattern_data|
  category_name = pattern_data.delete(:category)
  create_pattern(category_name, pattern_data)
  pattern_count += 1
end

# Create some inactive patterns for testing
puts "  🔒 Creating inactive patterns..."
inactive_patterns = [
  { category: "Alimentación", type: "merchant", value: "closed_restaurant",
    confidence: 3.0, usage_count: 50, success_count: 10, active: false },
  { category: "Compras", type: "keyword", value: "discontinued_store",
    confidence: 2.0, usage_count: 30, success_count: 5, active: false }
]

inactive_patterns.each do |pattern_data|
  category_name = pattern_data.delete(:category)
  create_pattern(category_name, pattern_data)
  pattern_count += 1
end

# Create user-created patterns
puts "  👤 Creating user-created patterns..."
user_patterns = [
  { category: "Alimentación", type: "merchant", value: "mi_restaurante_favorito",
    confidence: 4.0, usage_count: 25, success_count: 24, user_created: true },
  { category: "Transporte", type: "keyword", value: "mi_mecanico",
    confidence: 4.5, usage_count: 10, success_count: 10, user_created: true }
]

user_patterns.each do |pattern_data|
  category_name = pattern_data.delete(:category)
  create_pattern(category_name, pattern_data)
  pattern_count += 1
end

puts "✅ Created #{pattern_count} categorization patterns!"

# Display summary
puts "\n📊 Pattern Summary:"
CategorizationPattern::PATTERN_TYPES.each do |type|
  count = CategorizationPattern.where(pattern_type: type).count
  avg_success = CategorizationPattern.where(pattern_type: type).where("usage_count > 0").average(:success_rate)
  puts "  • #{type.capitalize}: #{count} patterns (avg success: #{(avg_success.to_f * 100).round(1)}%)"
end

puts "\n📈 Performance Metrics:"
total_patterns = CategorizationPattern.count
active_patterns = CategorizationPattern.active.count
high_performers = CategorizationPattern.where("success_rate >= ?", 0.8).count
categories_covered = Category.joins(:categorization_patterns).distinct.count
total_categories = Category.count

puts "  • Total patterns: #{total_patterns}"
puts "  • Active patterns: #{active_patterns}"
puts "  • High performers (>80% success): #{high_performers}"
puts "  • Category coverage: #{categories_covered}/#{total_categories} (#{(categories_covered.to_f / total_categories * 100).round(1)}%)"
