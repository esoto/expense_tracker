# frozen_string_literal: true

# Performance monitoring for test suite
# Automatically detects and reports slow tests
module PerformanceMonitor
  # Performance thresholds by test type
  THRESHOLDS = {
    unit: 0.02,         # Unit tests should be <20ms
    integration: 2.0,   # Integration tests should be <2s
    system: 5.0,        # System tests should be <5s
    default: 0.5        # Default threshold for uncategorized tests
  }.freeze

  # Warning thresholds (tests that are getting slow)
  WARNING_THRESHOLDS = {
    unit: 0.01,         # Warn at 10ms
    integration: 1.0,   # Warn at 1s
    system: 3.0,        # Warn at 3s
    default: 0.25       # Warn at 250ms
  }.freeze

  # Auto-fail threshold - any test exceeding this fails automatically
  AUTO_FAIL_THRESHOLD = 10.0

  class SlowTestError < StandardError; end

  class << self
    attr_accessor :slow_tests, :performance_report

    def reset!
      @slow_tests = []
      @performance_report = {
        total_tests: 0,
        slow_tests: 0,
        warned_tests: 0,
        failed_tests: 0,
        total_time: 0.0
      }
    end

    def record_test(example, duration)
      @performance_report[:total_tests] += 1
      @performance_report[:total_time] += duration

      test_type = determine_test_type(example)
      threshold = THRESHOLDS[test_type]
      warning_threshold = WARNING_THRESHOLDS[test_type]

      # Check for auto-fail condition
      if duration > AUTO_FAIL_THRESHOLD
        @performance_report[:failed_tests] += 1
        raise SlowTestError, format_slow_test_error(example, duration, AUTO_FAIL_THRESHOLD, :auto_fail)
      end

      # Check for threshold violations
      if duration > threshold
        @performance_report[:slow_tests] += 1
        @slow_tests << {
          description: example.full_description,
          location: example.location,
          duration: duration,
          threshold: threshold,
          test_type: test_type,
          severity: :error
        }
        
        # Log error to console (disabled for cleaner output)
        # puts format_slow_test_message(example, duration, threshold, :error)
      elsif duration > warning_threshold
        @performance_report[:warned_tests] += 1
        @slow_tests << {
          description: example.full_description,
          location: example.location,
          duration: duration,
          threshold: warning_threshold,
          test_type: test_type,
          severity: :warning
        }
        
        # Log warning to console (only in verbose mode)
        if ENV['VERBOSE_PERFORMANCE']
          puts format_slow_test_message(example, duration, warning_threshold, :warning)
        end
      end
    end

    def print_summary
      # Only show summary if explicitly requested
      return unless ENV['SHOW_PERFORMANCE_SUMMARY']

      puts "\n" + "=" * 80
      puts "PERFORMANCE MONITORING SUMMARY"
      puts "=" * 80

      puts "\nOverall Statistics:"
      puts "  Total Tests: #{@performance_report[:total_tests]}"
      puts "  Total Time: #{format_duration(@performance_report[:total_time])}"
      puts "  Average Time: #{format_duration(@performance_report[:total_time] / @performance_report[:total_tests])}"
      puts "  Slow Tests: #{@performance_report[:slow_tests]}"
      puts "  Warning Tests: #{@performance_report[:warned_tests]}"

      if @slow_tests.any?
        puts "\nSlow Tests (sorted by duration):"
        puts "-" * 80
        
        @slow_tests.sort_by { |t| -t[:duration] }.each_with_index do |test, index|
          severity_color = test[:severity] == :error ? "\e[31m" : "\e[33m"
          reset_color = "\e[0m"
          
          puts "#{severity_color}#{index + 1}. [#{test[:test_type].to_s.upcase}] #{test[:description]}#{reset_color}"
          puts "   Duration: #{format_duration(test[:duration])} (threshold: #{format_duration(test[:threshold])})"
          puts "   Location: #{test[:location]}"
          puts ""
        end
      end

      # Performance grades
      grade = calculate_performance_grade
      puts "\nPerformance Grade: #{grade[:letter]} (#{grade[:description]})"
      
      if grade[:recommendations].any?
        puts "\nRecommendations:"
        grade[:recommendations].each { |rec| puts "  • #{rec}" }
      end
      
      puts "=" * 80
    end

    private

    def determine_test_type(example)
      metadata = example.metadata
      
      # Check explicit metadata
      return :unit if metadata[:unit]
      return :integration if metadata[:integration]
      return :system if metadata[:system] || metadata[:type] == :system
      
      # Infer from type
      case metadata[:type]
      when :model, :service, :job
        :unit
      when :controller, :request
        :integration
      when :feature, :system
        :system
      else
        # Infer from file path
        case example.file_path
        when /spec\/models/, /spec\/services/, /spec\/jobs/, /spec\/lib/
          :unit
        when /spec\/controllers/, /spec\/requests/
          :integration
        when /spec\/system/, /spec\/features/
          :system
        else
          :default
        end
      end
    end

    def format_duration(seconds)
      if seconds < 0.001
        "#{(seconds * 1000000).round(1)}μs"
      elsif seconds < 1
        "#{(seconds * 1000).round(1)}ms"
      else
        "#{seconds.round(2)}s"
      end
    end

    def format_slow_test_message(example, duration, threshold, severity)
      severity_text = severity == :error ? "SLOW TEST" : "WARNING"
      severity_color = severity == :error ? "\e[31m" : "\e[33m"
      reset_color = "\e[0m"
      
      "#{severity_color}[#{severity_text}] #{example.full_description} - #{format_duration(duration)} (max: #{format_duration(threshold)})#{reset_color}"
    end

    def format_slow_test_error(example, duration, threshold, type)
      case type
      when :auto_fail
        "Test exceeded auto-fail threshold!\n" \
        "  Test: #{example.full_description}\n" \
        "  Duration: #{format_duration(duration)}\n" \
        "  Max allowed: #{format_duration(threshold)}\n" \
        "  Location: #{example.location}\n" \
        "\nThis test is critically slow and must be optimized immediately."
      end
    end

    def calculate_performance_grade
      slow_ratio = @performance_report[:slow_tests].to_f / @performance_report[:total_tests]
      warn_ratio = @performance_report[:warned_tests].to_f / @performance_report[:total_tests]
      
      grade = if slow_ratio == 0 && warn_ratio < 0.05
        { letter: "A+", description: "Excellent - All tests are blazing fast!" }
      elsif slow_ratio < 0.01 && warn_ratio < 0.1
        { letter: "A", description: "Great - Tests are well optimized" }
      elsif slow_ratio < 0.05 && warn_ratio < 0.2
        { letter: "B", description: "Good - Minor optimizations needed" }
      elsif slow_ratio < 0.1 && warn_ratio < 0.3
        { letter: "C", description: "Fair - Several tests need optimization" }
      elsif slow_ratio < 0.2
        { letter: "D", description: "Poor - Many slow tests detected" }
      else
        { letter: "F", description: "Critical - Immediate optimization required" }
      end
      
      # Add recommendations
      grade[:recommendations] = []
      
      if @slow_tests.any? { |t| t[:test_type] == :unit && t[:duration] > 0.05 }
        grade[:recommendations] << "Unit tests should not use real sleep/IO - use mocks/stubs"
      end
      
      if @slow_tests.any? { |t| t[:duration] > 5.0 }
        grade[:recommendations] << "Tests over 5s should be refactored or split"
      end
      
      if @performance_report[:total_time] > 60
        grade[:recommendations] << "Consider parallelizing test suite execution"
      end
      
      grade
    end
  end
end

# Initialize on load
PerformanceMonitor.reset!

# RSpec configuration
RSpec.configure do |config|
  # Record test performance
  config.around(:each) do |example|
    start_time = Time.current
    
    begin
      example.run
    ensure
      duration = Time.current - start_time
      PerformanceMonitor.record_test(example, duration) unless example.pending?
    end
  end
  
  # Print summary after suite
  config.after(:suite) do
    PerformanceMonitor.print_summary
  end
  
  # Reset before suite
  config.before(:suite) do
    PerformanceMonitor.reset!
  end
end