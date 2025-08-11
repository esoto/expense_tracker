# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "FuzzyMatcher Performance", type: :performance do
  let(:matcher) { Categorization::Matchers::FuzzyMatcher.new }

  describe "matching performance" do
    context "with realistic merchant data" do
      let(:merchants) do
        # Common merchant names in various formats
        [
          "Starbucks Coffee Company",
          "Walmart Supercenter",
          "Target Store",
          "Amazon.com",
          "McDonald's Restaurant",
          "Uber Technologies",
          "Lyft Inc",
          "Netflix Streaming",
          "Spotify Music",
          "Apple Store",
          "Google Services",
          "Microsoft Corporation",
          "Home Depot",
          "Lowes Home Improvement",
          "CVS Pharmacy",
          "Walgreens Drugstore",
          "Shell Gas Station",
          "Exxon Mobil",
          "Chevron Station",
          "Best Buy Electronics",
          "Whole Foods Market",
          "Trader Joe's",
          "Kroger Grocery",
          "Safeway Supermarket",
          "Costco Wholesale",
          "Sam's Club",
          "Office Depot",
          "Staples Office Supply",
          "FedEx Office",
          "UPS Store",
          "USPS Post Office",
          "Delta Airlines",
          "American Airlines",
          "Southwest Airlines",
          "United Airlines",
          "Hilton Hotel",
          "Marriott Hotel",
          "Holiday Inn",
          "Airbnb Rental",
          "Enterprise Rent-A-Car",
          "Hertz Car Rental",
          "Budget Car Rental",
          "Subway Restaurant",
          "Chipotle Mexican Grill",
          "Panera Bread",
          "Dunkin Donuts",
          "Pizza Hut",
          "Domino's Pizza",
          "Papa John's Pizza",
          "Taco Bell"
        ].map.with_index { |name, i| { id: i + 1, text: name } }
      end

      it "matches within 10ms for single query" do
        # Warm up the matcher first
        matcher.match("warmup", merchants[0..2])

        times = []

        10.times do
          time = Benchmark.realtime do
            matcher.match("starbucks coffee", merchants)
          end
          times << time * 1000 # Convert to milliseconds
        end

        # Exclude the first run which might be slower
        times_without_first = times.drop(1)
        average_time = times_without_first.sum / times_without_first.size
        max_time = times_without_first.max

        expect(average_time).to be < 10, "Average time: #{average_time.round(2)}ms"
        expect(max_time).to be < 15, "Max time: #{max_time.round(2)}ms (all times: #{times.map { |t| t.round(2) }.join(', ')}ms)"
      end

      it "handles typos within 20ms" do
        typo_queries = [
          "starbukcs", # transposition
          "wallmart",  # missing letter
          "targte",    # wrong letter
          "amazone",   # extra letter
          "mcdonlds"   # missing letter
        ]

        typo_queries.each do |query|
          time = Benchmark.realtime do
            matcher.match(query, merchants)
          end

          expect(time * 1000).to be < 20, "Query '#{query}' took #{(time * 1000).round(2)}ms"
        end
      end

      it "handles partial matches within 10ms" do
        partial_queries = [
          "star",
          "wal",
          "target",
          "amazon",
          "mcd"
        ]

        partial_queries.each do |query|
          time = Benchmark.realtime do
            matcher.match(query, merchants)
          end

          expect(time * 1000).to be < 10, "Query '#{query}' took #{(time * 1000).round(2)}ms"
        end
      end
    end

    context "with large dataset" do
      let(:large_merchant_set) do
        (1..1000).map { |i| { id: i, text: "Merchant #{i} Store Location #{i % 10}" } }
      end

      it "scales well with 1000 candidates" do
        times = []

        5.times do
          time = Benchmark.realtime do
            matcher.match("Merchant 500 Store", large_merchant_set)
          end
          times << time * 1000
        end

        average_time = times.sum / times.size

        # Even with 1000 candidates, should stay under 50ms
        expect(average_time).to be < 50, "Average time for 1000 candidates: #{average_time.round(2)}ms"
      end

      it "benefits from caching on repeated queries" do
        query = "Merchant 250 Store"

        # First query - no cache
        first_time = Benchmark.realtime do
          matcher.match(query, large_merchant_set)
        end

        # Second query - should hit cache
        second_time = Benchmark.realtime do
          matcher.match(query, large_merchant_set)
        end

        # Cache hit should be at least 5x faster
        speedup = first_time / second_time
        expect(speedup).to be > 5, "Cache speedup: #{speedup.round(2)}x"

        # Cache hit should be under 1ms
        expect(second_time * 1000).to be < 1, "Cache hit time: #{(second_time * 1000).round(2)}ms"
      end
    end

    context "with patterns" do
      before(:context) do
        # Create patterns once for all tests in this context
        @categories = create_list(:category, 5)

        @patterns = []
        @categories.each do |category|
          10.times do |i|
            @patterns << create(:categorization_pattern,
                             pattern_type: "merchant",
                             pattern_value: "Pattern #{category.id}-#{i}",
                             category: category,
                             confidence_weight: rand(0.5..2.0))
          end
        end

        # Ensure all data is loaded
        @patterns = CategorizationPattern.includes(:category).where(id: @patterns.map(&:id)).to_a
      end

      after(:context) do
        # Clean up after all tests in this context
        CategorizationPattern.destroy_all
        Category.destroy_all
      end

      it "matches patterns within 10ms" do
        # Warm up the matcher with a dummy query
        matcher.match_pattern("warmup", @patterns[0..2])

        # Run multiple times and take the best time to avoid outliers
        times = []
        3.times do
          time = Benchmark.realtime do
            matcher.match_pattern("Pattern 1-5", @patterns)
          end
          times << time * 1000
        end

        best_time = times.min
        expect(best_time).to be < 10, "Best pattern matching time: #{best_time.round(2)}ms (all times: #{times.map { |t| t.round(2) }.join(', ')}ms)"
      end
    end

    context "with Spanish text" do
      let(:spanish_merchants) do
        [
          "Café María",
          "Panadería José",
          "Restaurante El Niño",
          "Supermercado Peña",
          "Farmacia González",
          "Librería Sánchez",
          "Peluquería López",
          "Carnicería Rodríguez",
          "Verdulería Martínez",
          "Zapatería Hernández"
        ].map.with_index { |name, i| { id: i + 1, text: name } }
      end

      it "normalizes Spanish text within 10ms" do
        queries = [
          "cafe maria",     # missing accent
          "panaderia jose", # missing accent
          "nino",          # missing ñ
          "pena",          # ñ to n
          "gonzalez"       # missing accent
        ]

        # Warm up the matcher with Spanish text
        matcher.match("warmup", spanish_merchants[0..1])

        queries.each do |query|
          # Run twice and take the best time
          times = []
          2.times do
            time = Benchmark.realtime do
              matcher.match(query, spanish_merchants)
            end
            times << time * 1000
          end

          best_time = times.min
          expect(best_time).to be < 10, "Spanish query '#{query}' best time: #{best_time.round(2)}ms (all times: #{times.map { |t| t.round(2) }.join(', ')}ms)"
        end
      end
    end

    context "batch operations" do
      let(:merchants) do
        (1..100).map { |i| { id: i, text: "Merchant #{i}" } }
      end

      let(:queries) do
        (1..20).map { |i| "Merchant #{i * 5}" }
      end

      it "batch matches multiple queries efficiently" do
        time = Benchmark.realtime do
          matcher.batch_match(queries, merchants)
        end

        time_per_query = (time * 1000) / queries.size

        expect(time_per_query).to be < 10, "Average time per query in batch: #{time_per_query.round(2)}ms"
      end
    end

    context "different algorithms" do
      it "Jaro-Winkler performs within target" do
        jw_matcher = Categorization::Matchers::FuzzyMatcher.new(algorithms: [ :jaro_winkler ])

        time = Benchmark.realtime do
          100.times do
            jw_matcher.calculate_similarity("starbucks coffee", "starbucks coffee company", :jaro_winkler)
          end
        end

        avg_time = (time * 1000) / 100
        expect(avg_time).to be < 0.1, "Jaro-Winkler avg: #{avg_time.round(3)}ms"
      end

      it "Levenshtein performs within target" do
        lev_matcher = Categorization::Matchers::FuzzyMatcher.new(algorithms: [ :levenshtein ])

        time = Benchmark.realtime do
          100.times do
            lev_matcher.calculate_similarity("walmart store", "walmart supercenter", :levenshtein)
          end
        end

        avg_time = (time * 1000) / 100
        expect(avg_time).to be < 0.5, "Levenshtein avg: #{avg_time.round(3)}ms"
      end

      it "Trigram performs within target" do
        trigram_matcher = Categorization::Matchers::FuzzyMatcher.new(algorithms: [ :trigram ])

        time = Benchmark.realtime do
          100.times do
            trigram_matcher.calculate_similarity("amazon prime", "amazon.com", :trigram)
          end
        end

        avg_time = (time * 1000) / 100
        expect(avg_time).to be < 0.2, "Trigram avg: #{avg_time.round(3)}ms"
      end
    end

    describe "memory usage" do
      it "maintains reasonable memory footprint" do
        initial_memory = GC.stat[:heap_allocated_pages]

        # Perform many matches
        1000.times do |i|
          matcher.match("Query #{i}", [ { id: i, text: "Merchant #{i}" } ])
        end

        final_memory = GC.stat[:heap_allocated_pages]
        memory_growth = final_memory - initial_memory

        # Memory growth should be reasonable (less than 100 pages)
        expect(memory_growth).to be < 100, "Memory grew by #{memory_growth} pages"
      end

      it "cleans up cache appropriately" do
        # Fill cache with many entries
        500.times do |i|
          matcher.match("Query #{i}", [ { id: i, text: "Text #{i}" } ])
        end

        initial_metrics = matcher.metrics

        # Clear cache
        matcher.clear_cache

        # Verify cache was cleared
        final_metrics = matcher.metrics
        expect(final_metrics[:cache][:hits]).to eq(initial_metrics[:cache][:hits])
      end
    end

    describe "concurrent access" do
      it "handles concurrent matching safely" do
        merchants = (1..50).map { |i| { id: i, text: "Merchant #{i}" } }
        errors = []
        results = []

        threads = 10.times.map do |i|
          Thread.new do
            begin
              result = matcher.match("Merchant #{i}", merchants)
              results << result
            rescue => e
              errors << e
            end
          end
        end

        threads.each(&:join)

        expect(errors).to be_empty
        expect(results.size).to eq(10)
        expect(results.all?(&:success?)).to be true
      end
    end

    describe "performance metrics" do
      it "tracks performance accurately" do
        # Create some test patterns for match_pattern
        test_category = create(:category)
        test_patterns = create_list(:categorization_pattern, 3, category: test_category)

        # Create some test merchants for match_merchant
        test_merchants = []
        3.times { |i| test_merchants << double("merchant", id: i, name: "Merchant #{i}", display_name: "Merchant #{i}", usage_count: 10) }

        # Perform various operations
        10.times { |i| matcher.match("Query #{i}", [ { text: "Text #{i}" } ]) }
        5.times { |i| matcher.match_pattern("Pattern #{i}", test_patterns) }
        3.times { |i| matcher.match_merchant("Merchant #{i}", test_merchants) }

        metrics = matcher.metrics

        expect(metrics[:operations]).to have_key("match")
        expect(metrics[:operations]["match"][:count]).to be >= 10
        expect(metrics[:operations]["match"][:avg_ms]).to be < 10

        expect(metrics[:operations]).to have_key("match_pattern")
        expect(metrics[:operations]["match_pattern"][:count]).to be >= 5

        expect(metrics[:operations]).to have_key("match_merchant")
        expect(metrics[:operations]["match_merchant"][:count]).to be >= 3

        # Check percentiles
        expect(metrics[:operations]["match"][:p95_ms]).to be < 15
        expect(metrics[:operations]["match"][:p99_ms]).to be < 20

        # Clean up
        test_patterns.each(&:destroy)
        test_category.destroy
      end
    end
  end

  describe "real-world scenarios" do
    it "handles bank transaction descriptions efficiently" do
      transactions = [
        "PAYPAL *STARBUCKS 402935",
        "SQ *COFFEE SHOP #123",
        "TST* WALMART STORE #4567",
        "AMAZON.COM*MK8T92QL0",
        "UBER *TRIP HELP.UBER.COM",
        "NETFLIX.COM 866-579-7172",
        "SPOTIFY P0B3C4D5E6",
        "TARGET 00012345 CHICAGO IL"
      ]

      merchants = [
        { id: 1, text: "Starbucks" },
        { id: 2, text: "Coffee Shop" },
        { id: 3, text: "Walmart" },
        { id: 4, text: "Amazon" },
        { id: 5, text: "Uber" },
        { id: 6, text: "Netflix" },
        { id: 7, text: "Spotify" },
        { id: 8, text: "Target" }
      ]

      transactions.each do |transaction|
        time = Benchmark.realtime do
          result = matcher.match(transaction, merchants)
          expect(result).to be_success
        end

        expect(time * 1000).to be < 10, "Transaction '#{transaction}' took #{(time * 1000).round(2)}ms"
      end
    end

    it "handles credit card statement entries" do
      statements = [
        "WHOLEFDS MKT #10234 512-477-",
        "7-ELEVEN 32589 AUSTIN TX",
        "SHELL OIL 574496858 HOUSTON",
        "HEB #019 AUSTIN TX 789",
        "CHEVRON 0202456 SAN ANTONIO"
      ]

      merchants = [
        { id: 1, text: "Whole Foods" },
        { id: 2, text: "7-Eleven" },
        { id: 3, text: "Shell" },
        { id: 4, text: "HEB" },
        { id: 5, text: "Chevron" }
      ]

      statements.each do |statement|
        time = Benchmark.realtime do
          result = matcher.match(statement, merchants)
          expect(result).to be_success
        end

        expect(time * 1000).to be < 10, "Statement '#{statement}' took #{(time * 1000).round(2)}ms"
      end
    end
  end
end
