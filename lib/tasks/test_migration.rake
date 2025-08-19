# frozen_string_literal: true

require_relative "../../spec/support/configs/tier_auto_tagger"

namespace :test do
  desc "Automatically tag all tests with appropriate tier metadata"
  task tag_tests: :environment do
    puts "🏷️  Analyzing and tagging all test files..."

    spec_files = Dir["spec/**/*_spec.rb"]
    results = { unit: 0, integration: 0, performance: 0, system: 0, skipped: 0 }

    spec_files.each do |file|
      begin
        tier = TierAutoTagger.tag_file!(file)
        results[tier] += 1
      rescue => e
        puts "⚠️  Skipped #{file}: #{e.message}"
        results[:skipped] += 1
      end
    end

    puts "\n📊 Tagging Results:"
    results.each do |tier, count|
      emoji = { unit: "🧪", integration: "🔗", performance: "⚡", system: "🌐", skipped: "⚠️" }[tier]
      puts "  #{emoji} #{tier.to_s.capitalize}: #{count} files"
    end

    puts "\n✅ Test tagging completed!"
  end

  desc "Analyze current test structure and suggest improvements"
  task migrate_structure: :environment do
    puts "📋 Analyzing test structure..."

    spec_files = Dir["spec/**/*_spec.rb"]
    analysis = {
      by_tier: Hash.new(0),
      by_directory: Hash.new(0),
      slow_candidates: [],
      misplaced_files: []
    }

    spec_files.each do |file|
      tier = TierAutoTagger.analyze_file(file)
      directory = File.dirname(file).split("/")[1] # spec/models -> models

      analysis[:by_tier][tier] += 1
      analysis[:by_directory][directory] += 1

      # Check for potential issues
      if tier == :integration && directory == "models"
        analysis[:misplaced_files] << { file: file, issue: "Integration test in models directory" }
      elsif tier == :performance && !file.include?("performance")
        analysis[:misplaced_files] << { file: file, issue: "Performance test without clear naming" }
      end

      # Estimate slow tests (simple heuristic based on file size)
      file_size = File.size(file)
      if file_size > 10_000 && tier == :unit # Large files are often slow
        analysis[:slow_candidates] << { file: file, size: file_size, tier: tier }
      end
    end

    puts "\n📊 Current Distribution:"
    analysis[:by_tier].each do |tier, count|
      percentage = (count.to_f / spec_files.length * 100).round(1)
      puts "  #{tier.to_s.capitalize.ljust(12)} #{count.to_s.rjust(3)} files (#{percentage}%)"
    end

    puts "\n📁 By Directory:"
    analysis[:by_directory].sort_by { |_, count| -count }.each do |dir, count|
      puts "  #{dir.ljust(15)} #{count} files"
    end

    if analysis[:misplaced_files].any?
      puts "\n⚠️  Potentially Misplaced Files:"
      analysis[:misplaced_files].each do |item|
        puts "  #{item[:file]} - #{item[:issue]}"
      end
    end

    if analysis[:slow_candidates].any?
      puts "\n🐌 Potential Slow Unit Tests (>10KB files):"
      analysis[:slow_candidates].sort_by { |item| -item[:size] }.first(10).each do |item|
        size_kb = (item[:size] / 1024.0).round(1)
        puts "  #{item[:file]} (#{size_kb}KB)"
      end
    end

    puts "\n💡 Recommendations:"
    unit_percentage = (analysis[:by_tier][:unit].to_f / spec_files.length * 100).round(1)
    if unit_percentage < 60
      puts "  • Consider converting some integration tests to unit tests for faster feedback"
    end

    if analysis[:by_tier][:performance] > 20
      puts "  • Consider running performance tests separately from regular development workflow"
    end

    if analysis[:slow_candidates].length > 10
      puts "  • Review large test files for optimization opportunities"
    end
  end

  desc "Analyze test performance and identify optimization opportunities"
  task performance_analysis: :environment do
    puts "⏱️  Running performance analysis..."

    # Run a sample of tests with profiling
    sample_files = Dir["spec/**/*_spec.rb"].sample(10)

    puts "\n🔍 Profiling sample tests..."
    sample_files.each do |file|
      puts "\nAnalyzing #{file}..."

      # Run with profiling
      cmd = "bundle exec rspec #{file} --profile 3 --format json"
      result = `#{cmd} 2>&1`

      if $?.success?
        # Look for slow examples in output
        if result.include?("slowest examples")
          puts "  ⚠️  Contains slow examples"
        else
          puts "  ✅ Performance looks good"
        end
      else
        puts "  ❌ Failed to run"
      end
    end

    puts "\n📈 General Recommendations:"
    puts "  • Use build_stubbed instead of create in unit tests"
    puts "  • Mock external services and database calls"
    puts "  • Use let() instead of let!() when possible"
    puts "  • Consider using shared examples for common setups"
  end

  desc "Comprehensive test suite analysis with detailed recommendations"
  task analyze: :environment do
    puts "🔍 Comprehensive Test Suite Analysis"
    puts "=" * 50

    # Run all analysis tasks
    puts "\n1️⃣ STRUCTURE ANALYSIS"
    Rake::Task["test:migrate_structure"].invoke

    puts "\n\n2️⃣ TIER DISTRIBUTION"
    # Quick tier analysis without tagging
    spec_files = Dir["spec/**/*_spec.rb"]
    tier_counts = Hash.new(0)

    spec_files.each do |file|
      tier = TierAutoTagger.analyze_file(file)
      tier_counts[tier] += 1
    end

    puts "Current tier distribution (before tagging):"
    total = tier_counts.values.sum
    tier_counts.each do |tier, count|
      percentage = (count.to_f / total * 100).round(1)
      bar = "█" * (percentage / 2).to_i
      puts "  #{tier.to_s.capitalize.ljust(12)} #{count.to_s.rjust(3)} │#{bar.ljust(50)}│ #{percentage}%"
    end

    puts "\n\n3️⃣ OPTIMIZATION OPPORTUNITIES"

    # Check for common anti-patterns
    antipatterns = {
      excessive_creates: 0,
      no_let_usage: 0,
      large_files: 0,
      missing_stubs: 0
    }

    spec_files.each do |file|
      content = File.read(file)

      # Count create() usage (should be minimal in unit tests)
      create_count = content.scan(/\.create\(|FactoryBot\.create/).length
      antipatterns[:excessive_creates] += 1 if create_count > 5

      # Check for let() usage
      antipatterns[:no_let_usage] += 1 unless content.include?("let(")

      # Check file size
      antipatterns[:large_files] += 1 if File.size(file) > 20_000

      # Check for stubbing
      antipatterns[:missing_stubs] += 1 unless content.match?(/allow|stub|double|mock/)
    end

    puts "Anti-patterns found:"
    puts "  🏭 Files with excessive create() calls: #{antipatterns[:excessive_creates]}"
    puts "  📝 Files without let() usage: #{antipatterns[:no_let_usage]}"
    puts "  📊 Large files (>20KB): #{antipatterns[:large_files]}"
    puts "  🎭 Files without mocking/stubbing: #{antipatterns[:missing_stubs]}"

    puts "\n\n4️⃣ QUICK WINS"
    estimated_time_saved = 0

    if tier_counts[:unit] > 0
      unit_optimization_potential = antipatterns[:excessive_creates] + antipatterns[:missing_stubs]
      estimated_time_saved += unit_optimization_potential * 2 # 2 seconds per optimization
      puts "  ⚡ Unit test optimization potential: #{unit_optimization_potential} files (~#{unit_optimization_potential * 2}s faster)"
    end

    if tier_counts[:integration] > tier_counts[:unit]
      puts "  🔄 Consider converting some integration tests to unit tests"
      estimated_time_saved += 30
    end

    puts "  💰 Estimated time savings: ~#{estimated_time_saved} seconds per test run"

    puts "\n\n5️⃣ NEXT STEPS"
    puts "  1. Run 'rails test:tag_tests' to automatically tag all tests"
    puts "  2. Use 'bin/test-unit' for fast development feedback"
    puts "  3. Review files flagged above for optimization"
    puts "  4. Use 'bin/test-verify' after changes to measure improvements"
  end
end
