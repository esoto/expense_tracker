# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::PatternAnalytics, type: :service, unit: true do
  subject(:service) { described_class.new }

  describe "#generate_statistics" do
    context "with no patterns" do
      it "returns zero counts and an empty avg_success_rate" do
        stats = service.generate_statistics

        expect(stats[:total_patterns]).to eq(0)
        expect(stats[:active_count]).to eq(0)
        expect(stats[:inactive_count]).to eq(0)
        expect(stats[:avg_success_rate]).to eq(0.0)
        expect(stats[:patterns_by_type]).to eq({})
        expect(stats[:top_categories]).to eq([])
      end
    end

    context "with a mix of active and inactive patterns" do
      let(:category) { create(:category, name: "Food") }

      before do
        create_list(:categorization_pattern, 3, category: category, active: true,
                    usage_count: 10, success_count: 8, success_rate: 0.8)
        create_list(:categorization_pattern, 2, category: category, active: false,
                    usage_count: 0, success_count: 0, success_rate: 0.0)
      end

      it "returns the correct total count" do
        expect(service.generate_statistics[:total_patterns]).to eq(5)
      end

      it "returns correct active and inactive counts" do
        stats = service.generate_statistics
        expect(stats[:active_count]).to eq(3)
        expect(stats[:inactive_count]).to eq(2)
      end

      it "calculates avg_success_rate based on patterns with usage" do
        # 3 patterns × (8 successes / 10 uses) = 80%
        stats = service.generate_statistics
        expect(stats[:avg_success_rate]).to eq(80.0)
      end
    end

    context "patterns_by_type breakdown" do
      let(:category) { create(:category) }

      before do
        # Use explicit unique pattern_values to avoid uniqueness constraint violations
        # (PatternValidation downcases pattern_value before saving)
        create(:categorization_pattern, pattern_type: "merchant",    pattern_value: "starbucks",   category: category)
        create(:categorization_pattern, pattern_type: "merchant",    pattern_value: "mcdonald",    category: category)
        create(:categorization_pattern, pattern_type: "keyword",     pattern_value: "coffee",      category: category)
        create(:categorization_pattern, pattern_type: "description", pattern_value: "food expense", category: category)
      end

      it "groups patterns by type with correct counts" do
        by_type = service.generate_statistics[:patterns_by_type]
        expect(by_type["merchant"]).to eq(2)
        expect(by_type["keyword"]).to eq(1)
        expect(by_type["description"]).to eq(1)
      end
    end

    context "top_categories" do
      let(:cat_a) { create(:category, name: "Transport") }
      let(:cat_b) { create(:category, name: "Food") }
      let(:cat_c) { create(:category, name: "Entertainment") }

      before do
        create_list(:categorization_pattern, 5, category: cat_a)
        create_list(:categorization_pattern, 3, category: cat_b)
        create_list(:categorization_pattern, 1, category: cat_c)
      end

      it "returns categories sorted by pattern_count descending" do
        top = service.generate_statistics[:top_categories]
        names = top.map { |c| c[:name] }
        expect(names).to eq([ "Transport", "Food", "Entertainment" ])
      end

      it "returns the correct pattern_count for each category" do
        top = service.generate_statistics[:top_categories]
        transport = top.find { |c| c[:name] == "Transport" }
        expect(transport[:pattern_count]).to eq(5)
      end

      it "includes avg_success_rate for each category" do
        top = service.generate_statistics[:top_categories]
        top.each do |cat|
          expect(cat).to have_key(:avg_success_rate)
          expect(cat[:avg_success_rate]).to be_a(Float)
        end
      end

      it "limits results to 10 categories" do
        # Create 7 more categories (already have 3 above = 10 total)
        7.times do |i|
          cat = create(:category, name: "Category Extra #{i}")
          create(:categorization_pattern, category: cat)
        end

        top = service.generate_statistics[:top_categories]
        expect(top.size).to be <= 10
      end
    end

    context "avg_success_rate with no usage data" do
      let(:category) { create(:category) }

      before do
        create_list(:categorization_pattern, 3, category: category,
                    usage_count: 0, success_count: 0, success_rate: 0.0)
      end

      it "returns 0.0 when no patterns have been used" do
        expect(service.generate_statistics[:avg_success_rate]).to eq(0.0)
      end
    end
  end

  describe "#performance_over_time" do
    context "structure of return value" do
      it "returns a Hash with :daily, :weekly, and :summary keys" do
        result = service.performance_over_time
        expect(result).to have_key(:daily)
        expect(result).to have_key(:weekly)
        expect(result).to have_key(:summary)
      end

      it "daily is an Array spanning the last 30 days" do
        result = service.performance_over_time
        expect(result[:daily]).to be_an(Array)
        # Should have 31 entries (today + 30 prior days)
        expect(result[:daily].length).to eq(31)
      end

      it "each daily entry has the correct keys" do
        entry = service.performance_over_time[:daily].first
        expect(entry).to have_key(:date)
        expect(entry).to have_key(:total)
        expect(entry).to have_key(:correct)
        expect(entry).to have_key(:incorrect)
      end

      it "weekly is an Array of weekly aggregates" do
        weekly = service.performance_over_time[:weekly]
        expect(weekly).to be_an(Array)
        weekly.each do |week|
          expect(week).to have_key(:week_start)
          expect(week).to have_key(:total)
        end
      end

      it "summary contains total_matches and avg_daily" do
        summary = service.performance_over_time[:summary]
        expect(summary).to have_key(:total_matches)
        expect(summary).to have_key(:avg_daily)
      end
    end

    context "daily entries ordering" do
      it "returns daily entries in chronological order" do
        dates = service.performance_over_time[:daily].map { |d| d[:date] }
        expect(dates).to eq(dates.sort)
      end
    end

    context "when PatternFeedback records exist" do
      let(:category) { create(:category) }
      let(:pattern)  { create(:categorization_pattern, category: category) }

      # Pin created_at to a midday app-zone timestamp so the spec's Date
      # calculation and the service's Postgres DATE(created_at) bucket
      # agree regardless of when the suite runs. Using `N.days.ago` directly
      # is flaky near UTC-midnight wall times.
      let(:feedback_time) { 5.days.ago.beginning_of_day + 12.hours }

      before do
        create(:pattern_feedback, categorization_pattern: pattern, was_correct: true,
               created_at: feedback_time)
        create(:pattern_feedback, categorization_pattern: pattern, was_correct: true,
               created_at: feedback_time)
        create(:pattern_feedback, categorization_pattern: pattern, was_correct: false,
               created_at: feedback_time)
      end

      it "reflects feedback counts in the daily data for that date" do
        result     = service.performance_over_time
        five_days_ago = feedback_time.to_date.to_s
        day_entry  = result[:daily].find { |d| d[:date] == five_days_ago }

        expect(day_entry).not_to be_nil
        expect(day_entry[:correct]).to eq(2)
        expect(day_entry[:incorrect]).to eq(1)
        expect(day_entry[:total]).to eq(3)
      end

      it "summary total_matches equals the sum of all daily totals" do
        result = service.performance_over_time
        daily_total   = result[:daily].sum { |d| d[:total] }
        summary_total = result[:summary][:total_matches]
        expect(summary_total).to eq(daily_total)
      end
    end

    context "with no PatternFeedback records" do
      it "returns all zero totals" do
        result = service.performance_over_time
        result[:daily].each do |day|
          expect(day[:total]).to eq(0)
          expect(day[:correct]).to eq(0)
          expect(day[:incorrect]).to eq(0)
        end
      end

      it "returns zero for summary total_matches" do
        expect(service.performance_over_time[:summary][:total_matches]).to eq(0)
      end
    end

    context "avg_daily calculation" do
      it "is total_matches divided by PERFORMANCE_WINDOW_DAYS" do
        result      = service.performance_over_time
        expected    = (result[:summary][:total_matches].to_f / 30).round(2)
        expect(result[:summary][:avg_daily]).to eq(expected)
      end
    end
  end
end
