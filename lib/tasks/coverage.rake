# frozen_string_literal: true

namespace :coverage do
  desc "Run all test tiers and generate comprehensive coverage reports"
  task all: :environment do
    puts "🎯 Running comprehensive coverage analysis across all test tiers"
    puts "=" * 70
    puts "This will run all test suites and generate detailed coverage reports."
    puts "Estimated time: 10-20 minutes depending on test suite size."
    puts

    # Track overall start time
    overall_start = Time.now

    # Run each test tier
    tiers = %w[unit integration system performance]
    tier_results = {}

    tiers.each do |tier|
      puts "\n🔄 Running #{tier} tests with coverage tracking..."
      tier_start = Time.now

      result = system("bin/test-#{tier}")
      tier_duration = Time.now - tier_start

      tier_results[tier] = {
        success: result,
        duration: tier_duration
      }

      if result
        puts "✅ #{tier.capitalize} tests completed in #{tier_duration.round(1)}s"
      else
        puts "❌ #{tier.capitalize} tests failed after #{tier_duration.round(1)}s"
      end
    end

    # Generate combined analysis
    puts "\n🔄 Merging coverage results..."
    merge_result = system("bin/coverage-merge")

    puts "\n🔍 Analyzing coverage patterns..."
    analyze_result = system("bin/coverage-analyze")

    # Print final summary
    overall_duration = Time.now - overall_start

    puts "\n" + "=" * 70
    puts "🎯 COMPREHENSIVE COVERAGE ANALYSIS COMPLETE"
    puts "=" * 70
    puts "⏱️  Total time: #{overall_duration.round(1)}s"
    puts

    tier_results.each do |tier, result|
      status = result[:success] ? "✅" : "❌"
      puts "#{status} #{tier.capitalize.ljust(12)}: #{result[:duration].round(1)}s"
    end

    puts "\n📁 Generated Reports:"
    puts "   🌐 coverage/combined/index.html    - Combined HTML coverage report"
    puts "   📊 coverage/analysis_report.yml    - Detailed analysis (human readable)"
    puts "   📋 coverage/combined/coverage_matrix.json - Coverage by tier matrix"
    puts "   📈 coverage/combined/tier_comparison.json - Tier comparison data"

    if tier_results.values.all? { |r| r[:success] }
      puts "\n🎉 All test tiers completed successfully!"
    else
      failed_tiers = tier_results.select { |_, r| !r[:success] }.keys
      puts "\n⚠️  Some tiers failed: #{failed_tiers.join(', ')}"
      puts "   Check individual test output for details."
    end
  end

  desc "Run unit tests with coverage tracking"
  task unit: :environment do
    puts "🧪 Running unit tests with coverage tracking..."
    system("bin/test-unit")
  end

  desc "Run integration tests with coverage tracking"
  task integration: :environment do
    puts "🔗 Running integration tests with coverage tracking..."
    system("bin/test-integration")
  end

  desc "Run system tests with coverage tracking"
  task system: :environment do
    puts "🌐 Running system tests with coverage tracking..."
    system("bin/test-system")
  end

  desc "Run performance tests with coverage tracking"
  task performance: :environment do
    puts "⚡ Running performance tests with coverage tracking..."
    system("bin/test-performance")
  end

  desc "Merge coverage results from all tiers"
  task merge: :environment do
    puts "🔄 Merging coverage results from all test tiers..."
    system("bin/coverage-merge")
  end

  desc "Analyze coverage patterns across all tiers"
  task analyze: :environment do
    puts "🔍 Analyzing coverage patterns..."
    system("bin/coverage-analyze")
  end

  desc "Clean all coverage data"
  task clean: :environment do
    puts "🧹 Cleaning coverage data..."

    coverage_dirs = %w[coverage/unit coverage/integration coverage/system coverage/performance coverage/combined]
    coverage_dirs.each do |dir|
      if Dir.exist?(dir)
        FileUtils.rm_rf(dir)
        puts "  🗑️  Removed #{dir}"
      end
    end

    # Also clean root coverage files
    root_coverage_files = %w[coverage/.resultset.json coverage/analysis_report.json coverage/analysis_report.yml]
    root_coverage_files.each do |file|
      if File.exist?(file)
        File.delete(file)
        puts "  🗑️  Removed #{file}"
      end
    end

    puts "✅ Coverage data cleaned"
  end

  desc "Show coverage status for all tiers"
  task status: :environment do
    puts "📊 Coverage Status Across All Tiers"
    puts "=" * 50

    tiers = %w[unit integration system performance combined]

    tiers.each do |tier|
      tier_dir = "coverage/#{tier}"
      resultset_file = "#{tier_dir}/.resultset.json"

      print "#{tier.capitalize.ljust(12)}: "

      if File.exist?(resultset_file)
        begin
          resultset = JSON.parse(File.read(resultset_file))
          coverage_data = resultset.values.first

          if coverage_data && coverage_data["coverage"]
            file_count = coverage_data["coverage"].size
            timestamp = Time.at(coverage_data["timestamp"])

            # Calculate basic stats
            total_lines = 0
            covered_lines = 0

            coverage_data["coverage"].each do |file_path, file_data|
              next if file_path.include?("/spec/") || file_path.include?("/config/")

              # Handle both old and new SimpleCov formats
              line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
              next unless line_coverage

              total_lines += line_coverage.size
              covered_lines += line_coverage.compact.count { |hits| hits && hits > 0 }
            end

            percentage = total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(1) : 0
            age = ((Time.now - timestamp) / 60).round(1)

            status = case percentage
            when 90..100 then "🟢"
            when 80...90 then "🟡"
            when 70...80 then "🟠"
            else "🔴"
            end

            puts "#{status} #{percentage}% (#{file_count} files, #{age}m ago)"
          else
            puts "❌ Invalid data format"
          end
        rescue JSON::ParserError
          puts "❌ Corrupted data"
        rescue => e
          puts "❌ Error: #{e.message}"
        end
      else
        puts "⏳ No data (run rake coverage:#{tier})"
      end
    end

    puts "\n💡 Quick Commands:"
    puts "   rake coverage:all      - Run all tests with coverage"
    puts "   rake coverage:unit     - Unit tests only"
    puts "   rake coverage:merge    - Merge existing results"
    puts "   rake coverage:analyze  - Analyze coverage patterns"
    puts "   rake coverage:clean    - Clean all coverage data"
  end

  desc "Generate coverage report for CI/CD"
  task ci: :environment do
    puts "🤖 Generating CI/CD coverage report..."

    # Run unit tests (fast feedback)
    puts "Running unit tests for CI..."
    unit_result = system("bin/test-unit")

    unless unit_result
      puts "❌ Unit tests failed - stopping CI coverage"
      exit 1
    end

    # Generate basic analysis
    system("bin/coverage-analyze")

    # Output coverage percentage for CI systems
    resultset_file = "coverage/unit/.resultset.json"
    if File.exist?(resultset_file)
      resultset = JSON.parse(File.read(resultset_file))
      coverage_data = resultset.values.first["coverage"]

      total_lines = 0
      covered_lines = 0

      coverage_data.each do |file_path, file_data|
        next if file_path.include?("/spec/") || file_path.include?("/config/")

        # Handle both old and new SimpleCov formats
        line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
        next unless line_coverage

        total_lines += line_coverage.size
        covered_lines += line_coverage.compact.count { |hits| hits && hits > 0 }
      end

      percentage = total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(2) : 0

      puts "\n🎯 COVERAGE_PERCENTAGE=#{percentage}"
      puts "📊 TOTAL_LINES=#{total_lines}"
      puts "✅ COVERED_LINES=#{covered_lines}"

      # Set exit code based on coverage threshold
      if percentage < 80
        puts "❌ Coverage below 80% threshold"
        exit 1
      end
    end

    puts "✅ CI coverage analysis complete"
  end
end
