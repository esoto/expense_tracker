# frozen_string_literal: true

require "csv"

module Analytics
  # Exports analytics dashboard data in various formats
  class DashboardExporter
      attr_reader :analyzer, :format

      def initialize(analyzer, format: :csv)
        @analyzer = analyzer
        @format = format.to_sym
      end

      def export
        case format
        when :csv
          export_csv
        when :json
          export_json
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      private

      def export_csv
        CSV.generate do |csv|
          # Overall Metrics Section
          csv << [ "Pattern Analytics Report" ]
          csv << [ "Generated at:", Time.current.iso8601 ]
          csv << []

          # Overall metrics
          csv << [ "Overall Metrics" ]
          metrics = analyzer.overall_metrics
          csv << [ "Total Patterns", metrics[:total_patterns] ]
          csv << [ "Active Patterns", metrics[:active_patterns] ]
          csv << [ "Total Usage", metrics[:total_usage] ]
          csv << [ "Overall Accuracy", "#{metrics[:overall_accuracy]}%" ]
          csv << [ "Average Confidence", metrics[:average_confidence] ]
          csv << []

          # Category Performance
          csv << [ "Category Performance" ]
          csv << [ "Category", "Patterns", "Active", "Usage", "Success", "Accuracy %", "Avg Confidence" ]
          analyzer.category_performance.each do |cat|
            csv << [
              cat[:name],
              cat[:pattern_count],
              cat[:active_patterns],
              cat[:total_usage],
              cat[:total_success],
              cat[:accuracy],
              cat[:average_confidence]
            ]
          end
          csv << []

          # Pattern Type Analysis
          csv << [ "Pattern Type Analysis" ]
          csv << [ "Type", "Count", "Active", "Usage", "Success", "Accuracy %", "Avg Confidence" ]
          analyzer.pattern_type_analysis.each do |type|
            csv << [
              type[:type].humanize,
              type[:count],
              type[:active_count],
              type[:usage_count],
              type[:success_count],
              type[:accuracy],
              type[:average_confidence]
            ]
          end
          csv << []

          # Top Performing Patterns
          csv << [ "Top Performing Patterns" ]
          csv << [ "Pattern Type", "Pattern Value", "Category", "Usage", "Success", "Success Rate %", "Confidence", "User Created", "Active" ]
          analyzer.top_patterns.each do |pattern|
            csv << [
              pattern[:pattern_type],
              pattern[:pattern_value],
              pattern[:category_name],
              pattern[:usage_count],
              pattern[:success_count],
              pattern[:success_rate],
              pattern[:confidence_weight],
              pattern[:user_created] ? "Yes" : "No",
              pattern[:active] ? "Yes" : "No"
            ]
          end
          csv << []

          # Patterns Needing Improvement
          csv << [ "Patterns Needing Improvement" ]
          csv << [ "Pattern Type", "Pattern Value", "Category", "Usage", "Success", "Success Rate %", "Improvement Potential %", "User Created", "Active" ]
          analyzer.bottom_patterns.each do |pattern|
            csv << [
              pattern[:pattern_type],
              pattern[:pattern_value],
              pattern[:category_name],
              pattern[:usage_count],
              pattern[:success_count],
              pattern[:success_rate],
              pattern[:improvement_potential],
              pattern[:user_created] ? "Yes" : "No",
              pattern[:active] ? "Yes" : "No"
            ]
          end
          csv << []

          # Learning Metrics
          csv << [ "Learning Metrics" ]
          learning = analyzer.learning_metrics
          csv << [ "Total Learning Events", learning[:total_learning_events] ]
          csv << [ "Patterns Created", learning[:patterns_created] ]
          csv << [ "Patterns Improved", learning[:patterns_improved] ]
          csv << [ "Patterns Deactivated", learning[:patterns_deactivated] ]
          csv << [ "Average Confidence Gain", learning[:average_confidence_gain] ]
          csv << [ "Categories Improved", learning[:categories_improved] ]
        end
      end

      def export_json
        {
          metadata: {
            generated_at: Time.current.iso8601,
            time_range: {
              start: analyzer.time_range.first.iso8601,
              end: analyzer.time_range.last.iso8601
            }
          },
          overall_metrics: analyzer.overall_metrics,
          category_performance: analyzer.category_performance,
          pattern_type_analysis: analyzer.pattern_type_analysis,
          top_patterns: analyzer.top_patterns,
          bottom_patterns: analyzer.bottom_patterns,
          learning_metrics: analyzer.learning_metrics,
          trend_data: analyzer.trend_analysis,
          usage_heatmap: analyzer.usage_heatmap,
          recent_activity: analyzer.recent_activity(limit: 50)
        }.to_json
      end
  end
end
