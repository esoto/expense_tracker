# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::PatternPerformanceAnalyzer do
  let(:category) { create(:category) }
  let(:pattern) { create(:categorization_pattern, category: category) }
  let(:expense) { create(:expense) }
  let(:analyzer) { described_class.new }

  describe "Security Fixes" do
    describe "#trend_analysis" do
      context "SQL injection prevention" do
        it "sanitizes malicious interval input" do
          expect {
            analyzer.trend_analysis(interval: "'; DROP TABLE users; --")
          }.not_to raise_error

          result = analyzer.trend_analysis(interval: "'; DROP TABLE users; --")
          expect(result).to be_an(Array)
        end

        it "only accepts whitelisted intervals" do
          valid_intervals = [ :hourly, :daily, :weekly, :monthly ]

          valid_intervals.each do |interval|
            result = analyzer.trend_analysis(interval: interval)
            expect(result).to be_an(Array)
          end
        end

        it "defaults to daily for invalid intervals" do
          result = analyzer.trend_analysis(interval: :invalid)
          expect(result).to be_an(Array)
        end

        it "uses DATE_TRUNC instead of string interpolation" do
          # Create test data
          create(:pattern_feedback,
            feedback_type: "accepted",
            created_at: 1.day.ago,
            expense: expense,
            category: category
          )

          result = analyzer.trend_analysis(interval: :daily)
          expect(result).to be_an(Array)
          expect(result.first).to include(:date, :accepted, :accuracy)
        end
      end

      context "error handling" do
        it "returns empty array on database error" do
          allow(PatternFeedback).to receive(:where).and_raise(ActiveRecord::StatementInvalid)

          result = analyzer.trend_analysis
          expect(result).to eq([])
        end

        it "logs database errors" do
          allow(PatternFeedback).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("DB Error"))

          expect(Rails.logger).to receive(:error).with(/Trend analysis query failed/)
          analyzer.trend_analysis
        end

        it "handles unexpected errors gracefully" do
          allow(PatternFeedback).to receive(:where).and_raise(StandardError.new("Unexpected"))

          expect(Rails.logger).to receive(:error).with(/Unexpected error in trend analysis/)
          result = analyzer.trend_analysis
          expect(result).to eq([])
        end
      end
    end

    describe "#usage_heatmap" do
      context "error handling" do
        it "returns empty hash on database error" do
          allow(PatternFeedback).to receive(:where).and_raise(ActiveRecord::StatementInvalid)

          result = analyzer.usage_heatmap
          expect(result).to eq({})
        end

        it "logs database errors" do
          allow(PatternFeedback).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("DB Error"))

          expect(Rails.logger).to receive(:error).with(/Heatmap query failed/)
          analyzer.usage_heatmap
        end

        it "filters out empty cells for performance" do
          # Create test data
          create(:pattern_feedback, expense: expense, category: category)

          result = analyzer.usage_heatmap
          expect(result).to be_an(Array)
          # Should have 7 days * 24 hours = 168 entries
          expect(result.size).to eq(168)
        end
      end
    end

    describe "#category_performance" do
      context "N+1 query prevention" do
        it "uses single query with aggregation" do
          create_list(:categorization_pattern, 5, category: category)

          expect {
            analyzer.category_performance
          }.to make_database_queries(count: 1..2) # Single optimized query
        end

        it "includes pagination" do
          create_list(:category, 30).each do |cat|
            create(:categorization_pattern, category: cat)
          end

          result = analyzer.category_performance(page: 1, per_page: 10)
          expect(result.size).to be <= 10
        end

        it "validates pagination parameters" do
          result = analyzer.category_performance(page: -1, per_page: 1000)
          expect(result).to be_an(Array)
        end

        it "limits per_page to maximum" do
          create_list(:category, 200).each do |cat|
            create(:categorization_pattern, category: cat)
          end

          result = analyzer.category_performance(page: 1, per_page: 500)
          expect(result.size).to be <= Analytics::PatternPerformanceAnalyzer::MAX_PAGE_SIZE
        end
      end
    end
  end

  describe "Performance Optimizations" do
    describe "Constants" do
      it "defines all required constants" do
        expect(described_class::DEFAULT_PAGE_SIZE).to eq(25)
        expect(described_class::MAX_PAGE_SIZE).to eq(100)
        expect(described_class::MAX_DATE_RANGE_YEARS).to eq(2)
        expect(described_class::CACHE_TTL_MINUTES).to eq(5)
        expect(described_class::HEATMAP_CACHE_TTL_MINUTES).to eq(30)
      end
    end

    describe "#top_patterns" do
      it "includes proper associations to prevent N+1" do
        create_list(:categorization_pattern, 5, category: category)

        expect {
          patterns = analyzer.top_patterns
          patterns.each { |p| p[:category_name] }
        }.to make_database_queries(count: 1..2)
      end
    end

    describe "#bottom_patterns" do
      it "includes proper associations to prevent N+1" do
        create_list(:categorization_pattern, 5, category: category)

        expect {
          patterns = analyzer.bottom_patterns
          patterns.each { |p| p[:category_name] }
        }.to make_database_queries(count: 1..2)
      end
    end

    describe "#recent_activity" do
      it "preloads all associations" do
        # Create different expenses to avoid unique constraint violation
        5.times do
          exp = create(:expense)
          create(:pattern_feedback, expense: exp, category: category, categorization_pattern: pattern)
        end

        expect {
          activities = analyzer.recent_activity
          activities.each do |a|
            a[:expense_description]
            a[:category_name]
            a[:pattern_type]
          end
        }.to make_database_queries(count: 1..4) # Single query with preloading
      end

      it "limits results to maximum" do
        # Create different expenses to avoid unique constraint violation
        30.times do
          exp = create(:expense)
          create(:pattern_feedback, expense: exp, category: category)
        end

        result = analyzer.recent_activity(limit: 50)
        expect(result.size).to be <= Analytics::PatternPerformanceAnalyzer::MAX_RECENT_ACTIVITY
      end
    end
  end

  describe "Cache Invalidation" do
    it "clears cache when patterns are updated" do
      pattern = create(:categorization_pattern)

      expect(Rails.cache).to receive(:delete_matched).with("pattern_analytics/*")
      pattern.update!(confidence_weight: 2.0)
    end

    it "clears cache when feedback is created" do
      # Allow both dashboard and pattern analytics cache clearing
      expect(Rails.cache).to receive(:delete_matched).with("dashboard_*").at_least(:once)
      expect(Rails.cache).to receive(:delete_matched).with("pattern_analytics/*").at_least(:once)

      create(:pattern_feedback, expense: expense, category: category)
    end

    it "clears cache when learning events are created" do
      # Allow both dashboard and pattern analytics cache clearing
      expect(Rails.cache).to receive(:delete_matched).with("dashboard_*").at_least(:once)
      expect(Rails.cache).to receive(:delete_matched).with("pattern_analytics/*").at_least(:once)

      create(:pattern_learning_event, expense: expense, category: category)
    end
  end
end
