# frozen_string_literal: true

require "rails_helper"

RSpec.describe Categorization::Monitoring::DataQualityChecker do
  let(:checker) { described_class.new }

  # Create test data
  let!(:food_category) { create(:category, name: "Food") }
  let!(:transport_category) { create(:category, name: "Transport") }
  let!(:utilities_category) { create(:category, name: "Utilities") }
  let!(:empty_category) { create(:category, name: "Empty") }

  before do
    # Create diverse patterns for testing
    create_test_patterns
  end

  describe "#audit" do
    let(:result) { checker.audit }

    it "returns a comprehensive audit report" do
      expect(result).to include(
        :timestamp,
        :summary,
        :patterns,
        :categories,
        :coverage,
        :performance,
        :duplicates,
        :quality_score,
        :recommendations,
        :next_audit
      )
    end

    it "includes pattern statistics" do
      patterns = result[:patterns]
      expect(patterns).to include(
        :total,
        :active,
        :inactive,
        :by_type,
        :user_created,
        :system_created,
        :low_success,
        :unused,
        :high_performers
      )
      expect(patterns[:total]).to be > 0
    end

    it "includes category statistics" do
      categories = result[:categories]
      expect(categories).to include(
        :total,
        :with_patterns,
        :without_patterns,
        :avg_patterns_per_category
      )
      expect(categories[:without_patterns]).to eq(1) # empty_category
    end

    it "calculates coverage metrics" do
      coverage = result[:coverage]
      expect(coverage).to include(:ratio, :covered_categories, :total_categories)
      expect(coverage[:ratio]).to be_between(0, 1)
    end

    it "includes performance metrics" do
      performance = result[:performance]
      expect(performance).to include(
        :avg_success_rate,
        :median_success_rate,
        :total_usage,
        :total_successes,
        :patterns_by_performance,
        :learning_velocity
      )
    end

    it "includes quality score" do
      quality = result[:quality_score]
      expect(quality).to include(
        :overall,
        :components,
        :grade
      )
      expect(quality[:overall]).to be_between(0, 1)
      expect(quality[:grade]).to match(/[A-F]/)
    end

    it "generates recommendations" do
      expect(result[:recommendations]).to be_an(Array)
      result[:recommendations].each do |rec|
        expect(rec).to include(:type, :severity, :message, :action)
      end
    end
  end

  describe "#audit_patterns" do
    before { checker.audit_patterns }

    it "counts patterns by type" do
      by_type = checker.results[:patterns][:by_type]
      expect(by_type).to be_a(Hash)
      expect(by_type.keys).to include("merchant", "keyword")
    end

    it "identifies low success patterns" do
      low_success = checker.results[:patterns][:low_success]
      expect(low_success).to be >= 0
    end

    it "identifies unused patterns" do
      unused = checker.results[:patterns][:unused]
      expect(unused).to be >= 0
    end

    it "counts high performing patterns" do
      high_performers = checker.results[:patterns][:high_performers]
      expect(high_performers).to be >= 0
    end
  end

  describe "#audit_categories" do
    before { checker.audit_categories }

    it "counts categories with and without patterns" do
      results = checker.results[:categories]
      expect(results[:with_patterns]).to eq(3) # food, transport, utilities
      expect(results[:without_patterns]).to eq(1) # empty
    end

    it "calculates average patterns per category" do
      avg = checker.results[:categories][:avg_patterns_per_category]
      expect(avg).to be > 0
    end

    it "identifies categories below threshold" do
      below = checker.results[:categories][:categories_below_threshold]
      expect(below).to be >= 0
    end
  end

  describe "#audit_coverage" do
    before { checker.audit_coverage }

    it "calculates coverage ratio" do
      coverage = checker.results[:coverage]
      expect(coverage[:ratio]).to be_between(0.5, 1) # Most categories have patterns
    end

    it "identifies coverage gaps" do
      gaps = checker.results[:coverage][:gaps]
      expect(gaps[:categories_without_patterns]).to include("Empty")
    end

    it "calculates coverage by pattern type" do
      by_type = checker.results[:coverage][:coverage_by_type]
      expect(by_type).to be_a(Hash)
      expect(by_type["merchant"]).to include(:patterns, :categories_covered)
    end
  end

  describe "#audit_performance" do
    before do
      checker.audit_patterns # Required for some calculations
      checker.audit_performance
    end

    it "calculates average success rate" do
      avg = checker.results[:performance][:avg_success_rate]
      expect(avg).to be_between(0, 1)
    end

    it "calculates median success rate" do
      median = checker.results[:performance][:median_success_rate]
      expect(median).to be_between(0, 1)
    end

    it "groups patterns by performance" do
      groups = checker.results[:performance][:patterns_by_performance]
      expect(groups).to include(:excellent, :good, :fair, :poor)
      expect(groups.values.sum).to be > 0
    end

    it "calculates learning velocity" do
      velocity = checker.results[:performance][:learning_velocity]
      expect(velocity).to include(:new_patterns_per_day, :improved_patterns_per_day)
    end
  end

  describe "#audit_duplicates" do
    before do
      # Create duplicate patterns
      create(:categorization_pattern,
             category: food_category,
             pattern_type: "merchant",
             pattern_value: "duplicate_merchant")
      create(:categorization_pattern,
             category: transport_category,
             pattern_type: "merchant",
             pattern_value: "duplicate_merchant")

      checker.audit_duplicates
    end

    it "finds exact duplicates" do
      duplicates = checker.results[:duplicates]
      expect(duplicates[:exact_duplicates]).to be > 0
    end

    it "provides duplicate details" do
      details = checker.results[:duplicates][:duplicate_details]
      expect(details).to be_an(Array)
      duplicate = details.find { |d| d[:pattern_value] == "duplicate_merchant" }
      expect(duplicate).to be_present
      expect(duplicate[:count]).to eq(2)
    end

    it "finds similar patterns" do
      similar_count = checker.results[:duplicates][:similar_patterns]
      expect(similar_count).to be_a(Numeric)

      similar_clusters = checker.results[:duplicates][:similarity_clusters]
      expect(similar_clusters).to be_an(Array)
    end
  end

  describe "#calculate_quality_score" do
    before do
      checker.audit
    end

    it "calculates overall quality score" do
      score = checker.results[:quality_score][:overall]
      expect(score).to be_between(0, 1)
    end

    it "includes component scores" do
      components = checker.results[:quality_score][:components]
      expect(components).to include(
        :coverage,
        :success_rate,
        :diversity,
        :active_ratio,
        :freshness
      )

      components.each_value do |value|
        expect(value).to be_between(0, 1)
      end
    end

    it "assigns a quality grade" do
      grade = checker.results[:quality_score][:grade]
      expect(grade).to match(/[A-F]/)
    end
  end

  describe "#generate_recommendations" do
    before { checker.audit }

    it "generates actionable recommendations" do
      recommendations = checker.recommendations
      expect(recommendations).to be_an(Array)
    end

    it "includes severity levels" do
      recommendations = checker.recommendations
      if recommendations.any?
        severities = recommendations.map { |r| r[:severity] }
        expect(severities).to all(be_in([ :high, :medium, :low ]))
      end
    end

    it "provides specific actions" do
      recommendations = checker.recommendations
      if recommendations.any?
        actions = recommendations.map { |r| r[:action] }
        expect(actions).to all(be_a(Symbol))
      end
    end

    context "with poor data quality" do
      before do
        # Create patterns with poor performance
        5.times do
          create(:categorization_pattern,
                 category: food_category,
                 usage_count: 100,
                 success_count: 20,
                 success_rate: 0.2)
        end
        checker.audit
      end

      it "recommends improvements for low success rates" do
        rec = checker.recommendations.find { |r| r[:type] == :low_overall_success_rate }
        expect(rec).to be_present if checker.results[:performance][:avg_success_rate] < 0.5
      end
    end

    context "with coverage gaps" do
      before do
        # Ensure we have categories without patterns
        3.times { create(:category) }
        checker.audit
      end

      it "recommends adding patterns to categories" do
        rec = checker.recommendations.find { |r| r[:type] == :categories_without_patterns }
        expect(rec).to be_present
      end
    end
  end

  describe "#check_pattern_quality" do
    it "identifies low success rate issues" do
      pattern = create(:categorization_pattern,
                      usage_count: 100,
                      success_count: 30,
                      success_rate: 0.3)

      result = checker.check_pattern_quality(pattern)
      expect(result[:issues]).to include(
        a_hash_including(type: :low_success_rate)
      )
      expect(result[:quality]).to eq(:needs_attention)
    end

    it "identifies unused patterns" do
      pattern = create(:categorization_pattern,
                      usage_count: 0,
                      created_at: 60.days.ago)

      result = checker.check_pattern_quality(pattern)
      expect(result[:issues]).to include(
        a_hash_including(type: :unused)
      )
    end

    it "identifies short merchant patterns" do
      pattern = create(:categorization_pattern,
                      pattern_type: "merchant",
                      pattern_value: "ab")

      result = checker.check_pattern_quality(pattern)
      expect(result[:issues]).to include(
        a_hash_including(type: :too_short)
      )
    end

    it "marks good patterns as good quality" do
      pattern = create(:categorization_pattern,
                      usage_count: 100,
                      success_count: 85,
                      success_rate: 0.85,
                      pattern_type: "merchant",
                      pattern_value: "starbucks")

      result = checker.check_pattern_quality(pattern)
      expect(result[:issues]).to be_empty
      expect(result[:quality]).to eq(:good)
    end
  end

  private

  def create_test_patterns
    # High performing patterns
    3.times do |i|
      create(:categorization_pattern,
             category: food_category,
             pattern_type: "merchant",
             pattern_value: "food_merchant_#{i}",
             usage_count: 100,
             success_count: 90,
             success_rate: 0.9,
             confidence_weight: 4.0)
    end

    # Medium performing patterns
    2.times do |i|
      create(:categorization_pattern,
             category: transport_category,
             pattern_type: "keyword",
             pattern_value: "transport_keyword_#{i}",
             usage_count: 50,
             success_count: 30,
             success_rate: 0.6,
             confidence_weight: 2.0)
    end

    # Low performing patterns
    2.times do |i|
      create(:categorization_pattern,
             category: utilities_category,
             pattern_type: "description",
             pattern_value: "utility_desc_#{i}",
             usage_count: 20,
             success_count: 4,
             success_rate: 0.2,
             confidence_weight: 1.0)
    end

    # Unused patterns
    create(:categorization_pattern,
           category: food_category,
           pattern_type: "regex",
           pattern_value: "\\bunused\\b",
           usage_count: 0,
           success_count: 0,
           success_rate: 0,
           created_at: 45.days.ago)

    # Inactive pattern
    create(:categorization_pattern,
           category: transport_category,
           pattern_type: "amount_range",
           pattern_value: "10.00-50.00",
           active: false)

    # User-created pattern
    create(:categorization_pattern,
           category: food_category,
           pattern_type: "merchant",
           pattern_value: "user_merchant",
           user_created: true,
           usage_count: 10,
           success_count: 9,
           success_rate: 0.9)
  end
end
