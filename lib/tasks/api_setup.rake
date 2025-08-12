# frozen_string_literal: true

namespace :api do
  desc "Setup API v1 with sample data and tokens"
  task setup: :environment do
    puts "Setting up API v1..."

    # Create an API token for testing
    token = ApiToken.create!(
      name: "Development API Token",
      expires_at: 1.year.from_now
    )

    puts "\nAPI Token created:"
    puts "Name: #{token.name}"
    puts "Token: #{token.token}"
    puts "Expires: #{token.expires_at}"
    puts "\nSave this token - it won't be shown again!"

    # Create sample categories if they don't exist
    categories = [
      "Groceries",
      "Dining",
      "Transportation",
      "Entertainment",
      "Shopping",
      "Health",
      "Utilities",
      "Education"
    ].map do |name|
      Category.find_or_create_by!(name: name) do |cat|
        cat.color = "##{SecureRandom.hex(3)}"
      end
    end

    puts "\nCategories created/verified: #{categories.count}"

    # Create sample patterns
    pattern_data = [
      { type: "merchant", value: "walmart", category: "Groceries", weight: 2.0 },
      { type: "merchant", value: "target", category: "Shopping", weight: 1.8 },
      { type: "merchant", value: "starbucks", category: "Dining", weight: 2.5 },
      { type: "merchant", value: "uber", category: "Transportation", weight: 2.0 },
      { type: "keyword", value: "coffee", category: "Dining", weight: 1.5 },
      { type: "keyword", value: "grocery", category: "Groceries", weight: 1.5 },
      { type: "description", value: "movie", category: "Entertainment", weight: 1.8 },
      { type: "amount_range", value: "100-500", category: "Shopping", weight: 1.2 },
      { type: "amount_range", value: "5-20", category: "Dining", weight: 1.3 }
    ]

    patterns_created = 0
    pattern_data.each do |data|
      category = Category.find_by(name: data[:category])
      next unless category

      pattern = CategorizationPattern.find_or_create_by!(
        pattern_type: data[:type],
        pattern_value: data[:value],
        category: category
      ) do |p|
        p.confidence_weight = data[:weight]
        p.user_created = false
      end

      patterns_created += 1 if pattern.previously_new_record?
    end

    puts "Patterns created: #{patterns_created}"
    puts "Total patterns: #{CategorizationPattern.count}"

    puts "\n" + "="*50
    puts "API v1 Setup Complete!"
    puts "="*50
    puts "\nAPI Endpoints:"
    puts "  GET    /api/v1/patterns"
    puts "  GET    /api/v1/patterns/:id"
    puts "  POST   /api/v1/patterns"
    puts "  PATCH  /api/v1/patterns/:id"
    puts "  DELETE /api/v1/patterns/:id"
    puts "  POST   /api/v1/categorization/suggest"
    puts "  POST   /api/v1/categorization/feedback"
    puts "  POST   /api/v1/categorization/batch_suggest"
    puts "  GET    /api/v1/categorization/statistics"

    puts "\nRate Limits:"
    puts "  General API: 100 req/min per IP"
    puts "  Suggestions: 30 req/min per token"
    puts "  Batch: 10 req/min per token"
    puts "  Pattern creation: 20/hour per token"

    puts "\nExample cURL request:"
    puts <<~CURL

      curl -X POST http://localhost:3000/api/v1/categorization/suggest \\
        -H "Authorization: Bearer #{token.token}" \\
        -H "Content-Type: application/json" \\
        -d '{
          "merchant_name": "Walmart",
          "amount": 125.50,
          "max_suggestions": 3
        }'
    CURL

    puts "\nDocumentation: app/controllers/api/v1/API_DOCUMENTATION.md"
  end

  desc "Show API statistics"
  task stats: :environment do
    puts "\nAPI Statistics:"
    puts "="*50
    puts "Total API Tokens: #{ApiToken.count}"
    puts "Active Tokens: #{ApiToken.active.count}"
    puts "Valid Tokens: #{ApiToken.valid.count}"

    puts "\nCategorization Patterns:"
    puts "  Total: #{CategorizationPattern.count}"
    puts "  Active: #{CategorizationPattern.active.count}"
    puts "  User Created: #{CategorizationPattern.user_created.count}"
    puts "  High Confidence: #{CategorizationPattern.high_confidence.count}"
    puts "  Successful (>70%): #{CategorizationPattern.successful.count}"

    puts "\nPattern Types:"
    CategorizationPattern.group(:pattern_type).count.each do |type, count|
      puts "  #{type}: #{count}"
    end

    puts "\nFeedback Statistics:"
    puts "  Total Feedback: #{PatternFeedback.count}"
    puts "  Recent (7 days): #{PatternFeedback.where(created_at: 7.days.ago..).count}"

    if PatternFeedback.any?
      puts "\nFeedback Types:"
      PatternFeedback.group(:feedback_type).count.each do |type, count|
        puts "  #{type}: #{count}"
      end
    end

    puts "\nTop Categories by Pattern Count:"
    Category
      .joins(:categorization_patterns)
      .group("categories.name")
      .order("COUNT(categorization_patterns.id) DESC")
      .limit(5)
      .count
      .each do |name, count|
        puts "  #{name}: #{count} patterns"
      end
  end
end
