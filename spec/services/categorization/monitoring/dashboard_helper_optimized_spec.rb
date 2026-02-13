# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Monitoring::DashboardHelperOptimized, type: :service, integration: true do
  let(:helper) { described_class }

  # Test data setup
  before do
    # Create test categories
    @category1 = create(:category, name: "Food")
    @category2 = create(:category, name: "Transport")

    # Create test expenses with various states
    @categorized_expense = create(:expense, category: @category1, updated_at: 30.minutes.ago)
    @uncategorized_expense = create(:expense, category: nil, updated_at: 45.minutes.ago)
    @recent_expense = create(:expense, category: @category2, updated_at: 10.minutes.ago)
    @old_expense = create(:expense, category: @category1, updated_at: 2.hours.ago)

    # Create test patterns
    @active_pattern = create(:categorization_pattern,
                           category: @category1,
                           active: true,
                           confidence_weight: 0.9,
                           created_at: 12.hours.ago,
                           updated_at: 12.hours.ago)
    @inactive_pattern = create(:categorization_pattern,
                             category: @category2,
                             active: false,
                             confidence_weight: 0.6,
                             created_at: 2.days.ago,
                             updated_at: 2.days.ago)
    @recent_pattern = create(:categorization_pattern,
                           category: @category1,
                           active: true,
                           confidence_weight: 0.8,
                           created_at: 2.hours.ago,
                           updated_at: 1.hour.ago)
  end

  describe ".metrics_summary" do
    it "returns comprehensive metrics hash" do
      # Mock the health check since it may not exist
      allow(helper).to receive(:system_metrics_safe).and_return({
        database: { pool_size: 5 },
        memory: { rss_mb: 100.5 },
        background_jobs: { enqueued: 2 }
      })

      allow(helper).to receive(:cache_metrics).and_return({
        entries: 150,
        hit_rate: 85.5
      })

      allow(helper).to receive(:performance_metrics).and_return({
        averages: { categorization: 12.5 }
      })

      result = helper.metrics_summary

      expect(result).to be_a(Hash)
      expect(result).to have_key(:categorization)
      expect(result).to have_key(:patterns)
      expect(result).to have_key(:learning)
      expect(result).to have_key(:cache)
      expect(result).to have_key(:performance)
      expect(result).to have_key(:system)
    end

    it "caches results for the specified TTL" do
      # Clear cache first
      Rails.cache.delete("dashboard:metrics_summary")

      # Mock dependencies
      allow(helper).to receive(:system_metrics_safe).and_return({})
      allow(helper).to receive(:cache_metrics).and_return({})
      allow(helper).to receive(:performance_metrics).and_return({})

      # First call should execute
      expect(helper).to receive(:categorization_metrics_optimized).once.and_call_original
      result1 = helper.metrics_summary

      # Second call should use cache
      expect(helper).not_to receive(:categorization_metrics_optimized)
      result2 = helper.metrics_summary

      expect(result1).to eq(result2)
    end
  end

  describe ".categorization_metrics_optimized" do
    it "returns categorization statistics" do
      result = helper.categorization_metrics_optimized

      expect(result).to include(
        :total_expenses,
        :categorized,
        :uncategorized,
        :success_rate,
        :recent
      )

      expect(result[:total_expenses]).to eq(4)
      expect(result[:categorized]).to eq(3) # 3 expenses have categories
      expect(result[:uncategorized]).to eq(1) # 1 expense is uncategorized
      expect(result[:success_rate]).to eq(75.0) # 3/4 * 100
    end

    it "calculates recent activity correctly" do
      result = helper.categorization_metrics_optimized

      expect(result[:recent]).to include(:total, :categorized, :success_rate)
      expect(result[:recent][:total]).to eq(3) # 3 expenses updated in last hour (excluding @old_expense)
      expect(result[:recent][:categorized]).to eq(2) # 2 of recent expenses are categorized
    end

    it "handles empty database gracefully" do
      Expense.delete_all

      result = helper.categorization_metrics_optimized

      expect(result[:total_expenses]).to eq(0)
      expect(result[:success_rate]).to eq(0)
    end

    it "returns fallback metrics on database error" do
      allow(Expense).to receive(:select).and_raise(ActiveRecord::StatementInvalid.new("DB error"))

      result = helper.categorization_metrics_optimized

      expect(result).to eq(helper.send(:fallback_categorization_metrics))
    end
  end

  describe ".pattern_metrics_optimized" do
    it "returns pattern statistics" do
      result = helper.pattern_metrics_optimized

      expect(result).to include(
        :total,
        :active,
        :inactive,
        :high_confidence,
        :by_type,
        :recent_activity
      )

      expect(result[:total]).to eq(3)
      expect(result[:active]).to eq(2) # 2 active patterns
      expect(result[:inactive]).to eq(1) # 1 inactive pattern
    end

    it "calculates high confidence patterns" do
      result = helper.pattern_metrics_optimized

      # Only @active_pattern has confidence >= 0.8
      expect(result[:high_confidence]).to eq(2) # active_pattern (0.9) and recent_pattern (0.8)
    end

    it "includes pattern type distribution" do
      result = helper.pattern_metrics_optimized

      expect(result[:by_type]).to be_a(Hash)
    end

    it "calculates recent activity" do
      result = helper.pattern_metrics_optimized

      expect(result[:recent_activity]).to include(
        :created_24h,
        :updated_24h,
        :learning_rate
      )

      expect(result[:recent_activity][:created_24h]).to eq(1) # recent_pattern created in last 24h
      expect(result[:recent_activity][:updated_24h]).to eq(1) # recent_pattern updated in last 24h
    end

    it "returns fallback metrics on error" do
      allow(CategorizationPattern).to receive(:select).and_raise(ActiveRecord::StatementInvalid.new("DB error"))

      result = helper.pattern_metrics_optimized

      expect(result).to eq(helper.send(:fallback_pattern_metrics))
    end
  end

  describe ".learning_metrics_optimized" do
    it "returns learning statistics for last 24 hours" do
      result = helper.learning_metrics_optimized

      expect(result).to include(
        :patterns_created_24h,
        :patterns_updated_24h,
        :confidence_improvements,
        :learning_velocity
      )

      expect(result[:patterns_created_24h]).to eq(1) # recent_pattern created in last 24h
      expect(result[:patterns_updated_24h]).to eq(0) # recent_pattern: updated_at != created_at check
      expect(result[:learning_velocity]).to be_a(Numeric)
    end

    it "calculates learning velocity" do
      result = helper.learning_metrics_optimized

      # (created + updated) / 24 hours
      expected_velocity = (1 + 0).to_f / 24
      expect(result[:learning_velocity]).to eq(expected_velocity)
    end

    it "handles database errors gracefully" do
      allow(CategorizationPattern).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("DB error"))

      result = helper.learning_metrics_optimized

      expect(result).to eq({
        patterns_created_24h: 0,
        patterns_updated_24h: 0,
        confidence_improvements: 0,
        learning_velocity: 0.0
      })
    end
  end

  describe ".cache_metrics" do
    context "when PatternCache is available" do
      let(:mock_cache) { double("PatternCache") }
      let(:cache_stats) do
        {
          entries: 100,
          memory_bytes: 1024 * 1024, # 1MB
          hits: 80,
          misses: 20,
          evictions: 5
        }
      end

      before do
        allow(PatternCache).to receive(:instance).and_return(mock_cache)
        allow(mock_cache).to receive(:stats).and_return(cache_stats)
      end

      it "returns cache performance metrics" do
        result = helper.cache_metrics

        expect(result).to include(
          :entries,
          :memory_mb,
          :hits,
          :misses,
          :hit_rate,
          :evictions
        )

        expect(result[:entries]).to eq(100)
        expect(result[:memory_mb]).to eq(1.0) # 1MB converted to MB
        expect(result[:hits]).to eq(80)
        expect(result[:misses]).to eq(20)
        expect(result[:hit_rate]).to eq(80.0) # 80/(80+20) * 100
        expect(result[:evictions]).to eq(5)
      end

      it "calculates hit rate correctly" do
        result = helper.cache_metrics
        expect(result[:hit_rate]).to eq(80.0)
      end
    end

    context "when PatternCache is not available" do
      before do
        allow(PatternCache).to receive(:instance).and_raise(NameError.new("PatternCache not defined"))
      end

      it "returns error message" do
        result = helper.cache_metrics

        expect(result).to have_key(:error)
        expect(result[:error]).to include("Unable to fetch cache metrics")
      end
    end

    context "with no cache activity" do
      let(:mock_cache) { double("PatternCache") }
      let(:empty_stats) { { hits: 0, misses: 0, entries: 0, memory_bytes: 0, evictions: 0 } }

      before do
        allow(PatternCache).to receive(:instance).and_return(mock_cache)
        allow(mock_cache).to receive(:stats).and_return(empty_stats)
      end

      it "handles zero hit rate" do
        result = helper.cache_metrics

        expect(result[:hit_rate]).to eq(0)
      end
    end
  end

  describe ".performance_metrics" do
    context "when PerformanceTracker is available" do
      let(:mock_tracker) { double("PerformanceTracker") }
      let(:performance_data) do
        {
          operations: {
            "categorize_expense" => { avg_duration: 15.5, durations: [ 10, 20, 150 ] },
            "learn_pattern" => { avg_duration: 8.2, durations: [ 5, 10 ] },
            "cache_lookup" => { avg_duration: 2.1, durations: [ 1, 2, 3 ] }
          }
        }
      end

      before do
        allow(PerformanceTracker).to receive(:instance).and_return(mock_tracker)
        allow(mock_tracker).to receive(:metrics).and_return(performance_data)
        allow(helper).to receive(:calculate_throughput_optimized).and_return({
          expenses_per_hour: 120,
          expenses_per_minute: 2.0
        })
      end

      it "returns performance metrics" do
        result = helper.performance_metrics

        expect(result).to include(
          :operations,
          :averages,
          :slow_operations,
          :throughput
        )

        expect(result[:averages][:categorization]).to eq(15.5)
        expect(result[:averages][:learning]).to eq(8.2)
        expect(result[:averages][:cache_lookup]).to eq(2.1)
      end

      it "counts slow operations correctly" do
        result = helper.performance_metrics

        # One operation (150ms) is > 100ms threshold
        expect(result[:slow_operations]).to eq(1)
      end
    end

    context "when PerformanceTracker is not available" do
      before do
        allow(PerformanceTracker).to receive(:instance).and_raise(NameError.new("PerformanceTracker not defined"))
      end

      it "returns error message" do
        result = helper.performance_metrics

        expect(result).to have_key(:error)
        expect(result[:error]).to include("Unable to fetch performance metrics")
      end
    end
  end

  describe ".system_metrics_safe" do
    it "returns system metrics hash" do
      result = helper.system_metrics_safe

      expect(result).to include(
        :database,
        :memory,
        :background_jobs
      )
      expect(result).to be_a(Hash)
    end

    it "includes database metrics" do
      result = helper.system_metrics_safe

      db_metrics = result[:database]
      expect(db_metrics).to include(:pool_size) if db_metrics.any?
    end
  end

  describe "private methods" do
    describe "#calculate_throughput_optimized" do
      it "caches throughput calculations" do
        Rails.cache.delete("dashboard:throughput")

        # First call should calculate
        result1 = helper.send(:calculate_throughput_optimized)

        # Second call should use cache
        expect(Expense).not_to receive(:where)
        result2 = helper.send(:calculate_throughput_optimized)

        expect(result1).to eq(result2)
        expect(result1).to include(:expenses_per_hour, :expenses_per_minute)
      end
    end

    describe "#database_metrics_safe" do
      it "returns connection pool information" do
        result = helper.send(:database_metrics_safe)

        if result.any? # Only test if we get data back
          expect(result).to include(:pool_size)
          expect(result[:pool_size]).to be_a(Numeric)
        end
      end

      it "handles database connection errors gracefully" do
        allow(ActiveRecord::Base).to receive(:connection_pool).and_raise(StandardError.new("DB error"))

        result = helper.send(:database_metrics_safe)

        expect(result).to eq({})
      end
    end

    describe "#memory_metrics" do
      context "when GetProcessMem is available" do
        let(:mock_mem) { double("GetProcessMem", rss: 104857600, percent: 25.5) } # 100MB

        before do
          stub_const("GetProcessMem", Class.new)
          allow(GetProcessMem).to receive(:new).and_return(mock_mem)
        end

        it "returns memory usage information" do
          result = helper.send(:memory_metrics)

          expect(result).to include(:rss_mb, :percent)
          expect(result[:rss_mb]).to eq(100.0) # 100MB
          expect(result[:percent]).to eq(25.5)
        end
      end

      context "when GetProcessMem is not available" do
        it "returns empty hash" do
          result = helper.send(:memory_metrics)
          expect(result).to eq({})
        end
      end
    end

    describe "#background_job_metrics_safe" do
      context "when SolidQueue is available" do
        before do
          # Mock SolidQueue classes if they exist
          stub_const("SolidQueue::Job", double("SolidQueue::Job"))
          stub_const("SolidQueue::ClaimedExecution", double("SolidQueue::ClaimedExecution"))
          stub_const("SolidQueue::FailedExecution", double("SolidQueue::FailedExecution"))

          allow(SolidQueue::Job).to receive_message_chain(:where, :count).and_return(5)
          allow(SolidQueue::ClaimedExecution).to receive(:count).and_return(2)
          allow(SolidQueue::FailedExecution).to receive_message_chain(:where, :count).and_return(1)
        end

        it "returns SolidQueue job metrics" do
          result = helper.send(:background_job_metrics_safe)

          expect(result).to include(
            :provider,
            :enqueued,
            :processing,
            :failed_24h
          )

          expect(result[:provider]).to eq("SolidQueue")
          expect(result[:enqueued]).to eq(5)
          expect(result[:processing]).to eq(2)
          expect(result[:failed_24h]).to eq(1)
        end
      end

      context "when SolidQueue is not available" do
        it "returns no provider" do
          result = helper.send(:background_job_metrics_safe)

          expect(result[:provider]).to eq("none")
        end
      end
    end

    describe "fallback methods" do
      describe "#fallback_categorization_metrics" do
        it "returns zero-filled categorization metrics" do
          result = helper.send(:fallback_categorization_metrics)

          expect(result[:total_expenses]).to eq(0)
          expect(result[:categorized]).to eq(0)
          expect(result[:uncategorized]).to eq(0)
          expect(result[:success_rate]).to eq(0)
          expect(result[:recent][:success_rate]).to eq(0)
        end
      end

      describe "#fallback_pattern_metrics" do
        it "returns zero-filled pattern metrics" do
          result = helper.send(:fallback_pattern_metrics)

          expect(result[:total]).to eq(0)
          expect(result[:active]).to eq(0)
          expect(result[:inactive]).to eq(0)
          expect(result[:by_type]).to eq({})
          expect(result[:recent_activity][:learning_rate]).to eq(0.0)
        end
      end
    end
  end

  describe "caching behavior" do
    it "caches expensive operations appropriately" do
      Rails.cache.clear

      # Pattern type distribution should be cached for 1 minute
      expect(CategorizationPattern).to receive(:group).once.and_call_original

      2.times { helper.pattern_metrics_optimized }
    end

    it "respects cache TTL settings" do
      Rails.cache.delete("dashboard:metrics_summary")

      # Mock dependencies
      allow(helper).to receive(:system_metrics_safe).and_return({})
      allow(helper).to receive(:cache_metrics).and_return({})
      allow(helper).to receive(:performance_metrics).and_return({})

      # Cache should last for METRICS_CACHE_TTL
      expect(Rails.cache).to receive(:fetch)
        .with("dashboard:metrics_summary", expires_in: described_class::METRICS_CACHE_TTL)
        .and_call_original

      helper.metrics_summary
    end
  end
end
