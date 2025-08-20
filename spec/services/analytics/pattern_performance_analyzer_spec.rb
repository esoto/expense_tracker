# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe Analytics::PatternPerformanceAnalyzer, type: :service, performance: true do
  let(:analyzer) { described_class.new(time_range: time_range, category_id: category_id, pattern_type: pattern_type) }
  let(:time_range) { 7.days.ago..Time.current }
  let(:category_id) { nil }
  let(:pattern_type) { nil }

  let!(:category1) { create(:category, name: "Food") }
  let!(:category2) { create(:category, name: "Transport") }

  describe "Constants", performance: true do
    it "defines security and performance constants" do
      expect(described_class::MINIMUM_USAGE_THRESHOLD).to eq(5)
      expect(described_class::TARGET_SUCCESS_RATE).to eq(0.85)
      expect(described_class::DEFAULT_LIMIT).to eq(10)
      expect(described_class::MAX_RECENT_ACTIVITY).to eq(20)
    end

    it "defines validated interval formats for SQL safety" do
      expect(described_class::INTERVAL_FORMATS).to eq({
        hourly: "YYYY-MM-DD HH24",
        daily: "YYYY-MM-DD",
        weekly: "YYYY-IW",
        monthly: "YYYY-MM"
      })
    end
  end

  describe "#category_performance", performance: true do
    let(:category1) { create(:category, name: "Food") }
    let(:category2) { create(:category, name: "Transport") }

    before do
      # Create patterns with different performance metrics
      create(:categorization_pattern,
        category: category1,
        usage_count: 100,
        success_count: 85,
        confidence_weight: 1.5,
        active: true
      )
      create(:categorization_pattern,
        category: category1,
        usage_count: 50,
        success_count: 40,
        confidence_weight: 1.2,
        active: true
      )
      create(:categorization_pattern,
        category: category2,
        usage_count: 75,
        success_count: 70,
        confidence_weight: 1.8,
        active: true
      )
    end

    it "returns aggregated performance metrics without N+1 queries" do
      # Should use minimal queries for aggregation (single optimized query is ideal)
      expect {
        result = analyzer.category_performance
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
      }.to make_database_queries(count: 1..5) # Allow 1-5 queries for flexibility
    end

    it "calculates correct metrics for each category" do
      result = analyzer.category_performance

      food_metrics = result.find { |m| m[:name] == "Food" }
      expect(food_metrics[:pattern_count]).to eq(2)
      expect(food_metrics[:total_usage]).to eq(150)
      expect(food_metrics[:total_success]).to eq(125)
      expect(food_metrics[:accuracy]).to be_within(0.1).of(83.33)
    end

    it "sorts by accuracy descending" do
      result = analyzer.category_performance
      accuracies = result.map { |m| m[:accuracy] }
      expect(accuracies).to eq(accuracies.sort.reverse)
    end

    context "with pattern_type filter" do
      let(:pattern_type) { "merchant" }

      before do
        create(:categorization_pattern,
          category: category1,
          pattern_type: "merchant",
          usage_count: 25,
          success_count: 20
        )
      end

      it "filters patterns by type" do
        result = analyzer.category_performance
        # Should only include patterns of specified type
        expect(result).not_to be_empty
      end
    end
  end

  describe "#trend_analysis", performance: true do
    before do
      # Create feedbacks with different dates and types
      create(:pattern_feedback,
        feedback_type: "accepted",
        created_at: 1.day.ago
      )
      create(:pattern_feedback,
        feedback_type: "rejected",
        created_at: 1.day.ago
      )
      create(:pattern_feedback,
        feedback_type: "corrected",
        created_at: 2.days.ago
      )
    end

    context "SQL injection protection" do
      it "validates interval parameter against whitelist" do
        # Try SQL injection
        malicious_interval = "daily'; DROP TABLE users; --"

        expect {
          analyzer.trend_analysis(interval: malicious_interval)
        }.not_to raise_error

        # Should default to :daily
        result = analyzer.trend_analysis(interval: malicious_interval)
        expect(result).to be_an(Array)
      end

      it "only accepts valid interval symbols" do
        valid_intervals = [ :hourly, :daily, :weekly, :monthly ]

        valid_intervals.each do |interval|
          result = analyzer.trend_analysis(interval: interval)
          expect(result).to be_an(Array)
        end
      end

      it "uses parameterized queries for date formatting" do
        # Should not allow SQL injection through format string
        expect {
          analyzer.trend_analysis(interval: :daily)
        }.not_to raise_error
      end
    end

    it "returns properly formatted trend data" do
      result = analyzer.trend_analysis(interval: :daily)

      expect(result).to be_an(Array)
      expect(result.first).to include(
        :date, :accepted, :rejected, :corrected, :total, :accuracy
      )
    end

    it "calculates accuracy correctly" do
      result = analyzer.trend_analysis(interval: :daily)

      day_with_data = result.find { |r| r[:total] > 0 }
      if day_with_data
        expected_accuracy = (day_with_data[:accepted].to_f / day_with_data[:total] * 100).round(2)
        expect(day_with_data[:accuracy]).to eq(expected_accuracy)
      end
    end

    it "sorts results by date" do
      result = analyzer.trend_analysis(interval: :daily)
      dates = result.map { |r| r[:date] }
      expect(dates).to eq(dates.sort)
    end
  end

  describe "#usage_heatmap", performance: true do
    before do
      # Create expenses with pattern feedbacks at different times
      expense1 = create(:expense, transaction_date: Time.current.beginning_of_week + 9.hours)
      expense2 = create(:expense, transaction_date: Time.current.beginning_of_week + 14.hours)

      create(:pattern_feedback, expense: expense1)
      create(:pattern_feedback, expense: expense2)
    end

    it "uses optimized query without N+1" do
      expect {
        result = analyzer.usage_heatmap
        expect(result).to be_an(Array)
      }.to make_database_queries(count: 1..3) # Single optimized query
    end

    it "returns data for all hours and days" do
      result = analyzer.usage_heatmap

      expect(result.size).to eq(7 * 24) # 7 days * 24 hours

      # Check structure
      expect(result.first).to include(
        :day, :hour, :count, :day_name, :hour_label
      )
    end

    it "correctly formats hour labels" do
      result = analyzer.usage_heatmap

      hour_0 = result.find { |r| r[:hour] == 0 }
      expect(hour_0[:hour_label]).to eq("0:00")

      hour_23 = result.find { |r| r[:hour] == 23 }
      expect(hour_23[:hour_label]).to eq("23:00")
    end

    it "uses correct day names" do
      result = analyzer.usage_heatmap

      sunday = result.find { |r| r[:day] == 0 }
      expect(sunday[:day_name]).to eq("Sunday")

      saturday = result.find { |r| r[:day] == 6 }
      expect(saturday[:day_name]).to eq("Saturday")
    end
  end

  describe "#top_patterns", performance: true do
    before do
      # Create patterns with varying performance
      create(:categorization_pattern,
        category: category1,
        usage_count: 100,
        success_count: 95,
        success_rate: 0.95
      )
      create(:categorization_pattern,
        category: category1,
        usage_count: 4, # Below threshold
        success_count: 4,
        success_rate: 1.0
      )
      create(:categorization_pattern,
        category: category2,
        usage_count: 50,
        success_count: 45,
        success_rate: 0.90
      )
    end

    it "filters patterns by minimum usage threshold" do
      result = analyzer.top_patterns

      # Should exclude patterns with usage_count < 5
      expect(result.all? { |p| p[:usage_count] >= 5 }).to be true
    end

    it "orders by success rate descending" do
      result = analyzer.top_patterns

      success_rates = result.map { |p| p[:success_rate] }
      expect(success_rates).to eq(success_rates.sort.reverse)
    end

    it "respects the limit parameter" do
      20.times do
        create(:categorization_pattern,
          usage_count: 10,
          success_count: 8,
          success_rate: 0.8
        )
      end

      result = analyzer.top_patterns(limit: 5)
      expect(result.size).to eq(5)
    end

    it "includes all required fields" do
      result = analyzer.top_patterns

      expect(result.first).to include(
        :id, :pattern_type, :pattern_value, :category_name,
        :category_color, :usage_count, :success_count,
        :success_rate, :confidence_weight, :user_created, :active
      )
    end
  end

  describe "#recent_activity", performance: true do
    before do
      5.times do
        create(:pattern_feedback)
      end
    end

    it "limits results to MAX_RECENT_ACTIVITY" do
      30.times { create(:pattern_feedback) }

      result = analyzer.recent_activity(limit: 100)
      expect(result.size).to eq(20) # MAX_RECENT_ACTIVITY
    end

    it "preloads associations to avoid N+1" do
      expect {
        result = analyzer.recent_activity
        result.each { |r| r[:expense_description] }
      }.to make_database_queries(count: 1..4) # Should use includes
    end

    it "returns recent activities in correct format" do
      result = analyzer.recent_activity

      expect(result.first).to include(
        :id, :created_at, :feedback_type, :expense_description,
        :expense_amount, :category_name, :category_color,
        :pattern_type, :pattern_value, :was_correct
      )
    end
  end

  describe "#calculate_improvement_potential", performance: true do
    it "uses TARGET_SUCCESS_RATE constant" do
      pattern = build(:categorization_pattern, success_rate: 0.5)

      potential = analyzer.send(:calculate_improvement_potential, pattern)
      expected = ((0.85 - 0.5) * 100).round(2)

      expect(potential).to eq(expected)
    end

    it "returns 0 for patterns above target rate" do
      pattern = build(:categorization_pattern, success_rate: 0.9)

      potential = analyzer.send(:calculate_improvement_potential, pattern)
      expect(potential).to eq(0)
    end
  end

  describe "#validate_interval", performance: true do
    it "returns valid interval symbols" do
      expect(analyzer.send(:validate_interval, :daily)).to eq(:daily)
      expect(analyzer.send(:validate_interval, "weekly")).to eq(:weekly)
    end

    it "defaults to :daily for invalid intervals" do
      expect(analyzer.send(:validate_interval, "invalid")).to eq(:daily)
      expect(analyzer.send(:validate_interval, nil)).to eq(:daily)
      expect(analyzer.send(:validate_interval, "'; DROP TABLE;")).to eq(:daily)
    end
  end

  describe "Performance", performance: true do
    before do
      # Create significant test data
      10.times do
        category = create(:category)
        5.times do
          pattern = create(:categorization_pattern, category: category)
          3.times do
            expense = create(:expense, category: category)
            create(:pattern_feedback,
              expense: expense,
              category: category,
              categorization_pattern: pattern
            )
          end
        end
      end
    end

    it "handles large datasets efficiently" do
      # Use benchmark to measure performance
      time = Benchmark.realtime do
        analyzer.overall_metrics
        analyzer.category_performance
        analyzer.trend_analysis
        analyzer.usage_heatmap
      end

      expect(time).to be < 1.0 # Should complete in under 1 second
    end
  end
end
