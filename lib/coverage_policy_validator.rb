# frozen_string_literal: true

require "yaml"
require "json"

# Coverage Policy Validator
# Enforces coverage thresholds and quality gates defined in coverage_policy.yml
class CoveragePolicyValidator
  attr_reader :policy, :violations, :warnings

  def initialize(policy_file = "config/coverage_policy.yml")
    @policy = YAML.load_file(policy_file)
    @violations = []
    @warnings = []
  end

  # Validate coverage for a specific tier
  def validate_tier(tier, coverage_data = nil)
    coverage_data ||= load_coverage_data(tier)

    unless coverage_data
      add_violation(:missing_data, tier, "No coverage data found for #{tier} tier")
      return false
    end

    tier_policy = @policy["tiers"][tier]
    unless tier_policy
      add_warning(:no_policy, tier, "No policy defined for #{tier} tier")
      return true
    end

    validate_overall_coverage(tier, coverage_data, tier_policy)
    validate_per_file_coverage(tier, coverage_data, tier_policy)
    validate_critical_files(tier, coverage_data, tier_policy)
    validate_protected_files(tier, coverage_data) if tier == "combined"
    validate_custom_rules(tier, coverage_data)

    @violations.empty?
  end

  # Validate all available tiers
  def validate_all_tiers
    results = {}

    @policy["tiers"].keys.each do |tier|
      puts "🔍 Validating #{tier} tier coverage..."
      results[tier] = validate_tier(tier)
    end

    generate_validation_report(results)
    results.values.all?
  end

  # Check if coverage drop is acceptable
  def validate_coverage_drop(tier, old_percentage, new_percentage)
    return true unless @policy["quality_gates"]["enforce_minimum"]

    allowed_drop = @policy["quality_gates"]["allowed_drop_percentage"]
    actual_drop = old_percentage - new_percentage

    if actual_drop > allowed_drop
      add_violation(
        :coverage_drop,
        tier,
        "Coverage dropped by #{actual_drop.round(2)}% (allowed: #{allowed_drop}%)"
      )
      return false
    end

    true
  end

  # Generate enforcement report
  def generate_enforcement_report
    report = {
      timestamp: Time.now.iso8601,
      policy_version: @policy.dig("global", "version") || "1.0",
      violations: @violations,
      warnings: @warnings,
      enforcement_summary: {
        total_violations: @violations.size,
        total_warnings: @warnings.size,
        critical_violations: @violations.count { |v| v[:severity] == :critical },
        status: @violations.empty? ? "PASSED" : "FAILED"
      }
    }

    # Save detailed report
    File.write("coverage/policy_enforcement.json", JSON.pretty_generate(report))

    # Generate human-readable summary
    generate_readable_enforcement_summary(report)

    report
  end

  private

  # Entries recorded within this window of the newest one are treated as the
  # same run. Parallel workers of one run finish seconds apart; distinct runs
  # are minutes-to-hours apart.
  SAME_RUN_WINDOW_SECONDS = 600

  def load_coverage_data(tier)
    resultset_file = "coverage/#{tier}/.resultset.json"
    return nil unless File.exist?(resultset_file)

    begin
      resultset = JSON.parse(File.read(resultset_file))
      merge_latest_run(resultset)
    rescue JSON::ParserError, StandardError
      nil
    end
  end

  # SimpleCov accumulates one resultset entry per command_name. A serial run
  # produces a single entry, but a parallel_rspec run (bin/test-unit,
  # bin/test-integration) produces one entry PER WORKER — taking only the
  # last entry would report a single worker's file slice as the whole run.
  # Merge every entry from the latest run, summing per-line hit counts the
  # same way SimpleCov's own result merger does. Returns {file => lines_array}
  # (the pre-existing "old format" shape both validators already handle).
  def merge_latest_run(resultset)
    newest = resultset.values.map { |entry| entry["timestamp"].to_i }.max
    same_run = resultset.values.select do |entry|
      newest - entry["timestamp"].to_i <= SAME_RUN_WINDOW_SECONDS
    end

    merged = {}
    same_run.each do |entry|
      entry["coverage"].each do |file_path, file_data|
        lines = file_data.is_a?(Array) ? file_data : file_data["lines"]
        next unless lines

        merged[file_path] = if merged.key?(file_path)
          merged[file_path].zip(lines).map do |a, b|
            # SimpleCov::Combine::LinesCombiner semantics: when entries
            # disagree on relevance (0 in one, nil in another — bootsnap
            # ISeq caching causes this across workers), the line is NOT
            # relevant. Naive to_i summing would count it as uncovered
            # and inflate the denominator.
            sum = a.to_i + b.to_i
            sum.zero? && (a.nil? || b.nil?) ? nil : sum
          end
        else
          lines
        end
      end
    end
    merged
  end

  def validate_overall_coverage(tier, coverage_data, tier_policy)
    total_lines = 0
    covered_lines = 0

    coverage_data.each do |file_path, file_data|
      next if should_exclude_file?(file_path)

      # Handle both old and new SimpleCov formats
      line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
      next unless line_coverage

      # Only count relevant (executable) lines — nil entries are comments/blanks
      relevant = line_coverage.compact
      total_lines += relevant.size
      covered_lines += relevant.count { |hits| hits > 0 }
    end

    return if total_lines.zero?

    overall_percentage = (covered_lines.to_f / total_lines * 100)
    minimum = tier_policy["minimum_overall"]

    if overall_percentage < minimum
      add_violation(
        :overall_coverage,
        tier,
        "Overall coverage #{overall_percentage.round(2)}% below minimum #{minimum}%"
      )
    end
  end

  def validate_per_file_coverage(tier, coverage_data, tier_policy)
    minimum_per_file = tier_policy["minimum_per_file"]
    critical_threshold = tier_policy["critical_threshold"]

    coverage_data.each do |file_path, file_data|
      next if should_exclude_file?(file_path)

      # Handle both old and new SimpleCov formats
      line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
      next unless line_coverage

      # Only count relevant (executable) lines
      relevant = line_coverage.compact
      total_lines = relevant.size
      next if total_lines.zero?

      covered_lines = relevant.count { |hits| hits > 0 }
      percentage = (covered_lines.to_f / total_lines * 100)

      if percentage < critical_threshold
        add_violation(
          :critical_file,
          tier,
          "#{file_path}: #{percentage.round(1)}% (critical threshold: #{critical_threshold}%)",
          severity: :critical
        )
      elsif percentage < minimum_per_file
        add_violation(
          :low_file_coverage,
          tier,
          "#{file_path}: #{percentage.round(1)}% (minimum: #{minimum_per_file}%)"
        )
      end
    end
  end

  def validate_critical_files(tier, coverage_data, tier_policy)
    focus_areas = tier_policy["focus_areas"] || []

    focus_areas.each do |pattern|
      matching_files = coverage_data.keys.select { |file| file.include?(pattern) }

      if matching_files.empty?
        add_warning(
          :no_focus_coverage,
          tier,
          "No coverage found for focus area: #{pattern}"
        )
      end
    end
  end

  def validate_protected_files(tier, coverage_data)
    protected_files = @policy["quality_gates"]["protected_files"] || []
    minimum = @policy["quality_gates"]["protected_file_minimum"]

    protected_files.each do |file_pattern|
      matching_files = coverage_data.keys.select { |file| file.include?(file_pattern) }

      matching_files.each do |file_path|
        file_data = coverage_data[file_path]
        line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
        next unless line_coverage

        relevant = line_coverage.compact
        total_lines = relevant.size
        next if total_lines.zero?

        covered_lines = relevant.count { |hits| hits > 0 }
        percentage = (covered_lines.to_f / total_lines * 100)

        if percentage < minimum
          add_violation(
            :protected_file,
            tier,
            "Protected file #{file_path}: #{percentage.round(1)}% (required: #{minimum}%)",
            severity: :critical
          )
        end
      end
    end
  end

  def validate_custom_rules(tier, coverage_data)
    custom_rules = @policy["custom_rules"] || {}

    # Validate files requiring full coverage
    full_coverage_files = custom_rules["require_full_coverage"] || []
    full_coverage_files.each do |file_pattern|
      matching_files = coverage_data.keys.select { |file| file.include?(file_pattern) }

      matching_files.each do |file_path|
        file_data = coverage_data[file_path]
        line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
        next unless line_coverage

        relevant = line_coverage.compact
        total_lines = relevant.size
        next if total_lines.zero?

        covered_lines = relevant.count { |hits| hits > 0 }
        percentage = (covered_lines.to_f / total_lines * 100)

        if percentage < 100
          add_violation(
            :full_coverage_required,
            tier,
            "#{file_path}: #{percentage.round(1)}% (100% required)",
            severity: :critical
          )
        end
      end
    end

    # Validate complex files
    complexity_threshold = custom_rules["complexity_line_threshold"] || 100
    high_complexity_min = custom_rules["high_complexity_min_coverage"] || 95

    coverage_data.each do |file_path, file_data|
      next if should_exclude_file?(file_path)

      # Handle both old and new SimpleCov formats
      line_coverage = file_data.is_a?(Array) ? file_data : file_data["lines"]
      next unless line_coverage

      # Only count relevant (executable) lines
      relevant = line_coverage.compact
      total_lines = relevant.size
      next if total_lines < complexity_threshold

      covered_lines = relevant.count { |hits| hits > 0 }
      percentage = (covered_lines.to_f / total_lines * 100)

      if percentage < high_complexity_min
        add_violation(
          :complex_file_coverage,
          tier,
          "Complex file #{file_path} (#{total_lines} lines): #{percentage.round(1)}% (required: #{high_complexity_min}%)"
        )
      end
    end
  end

  def should_exclude_file?(file_path)
    exclude_patterns = @policy["global"]["exclude_patterns"] || []
    force_include_patterns = @policy["global"]["force_include_patterns"] || []

    # Check force include first
    return false if force_include_patterns.any? { |pattern| file_path.include?(pattern) }

    # Then check exclude patterns
    exclude_patterns.any? { |pattern| file_path.include?(pattern) }
  end

  def add_violation(type, tier, message, severity: :normal)
    @violations << {
      type: type,
      tier: tier,
      message: message,
      severity: severity,
      timestamp: Time.now.iso8601
    }
  end

  def add_warning(type, tier, message)
    @warnings << {
      type: type,
      tier: tier,
      message: message,
      timestamp: Time.now.iso8601
    }
  end

  def generate_validation_report(results)
    puts "\n" + "=" * 60
    puts "📋 COVERAGE POLICY VALIDATION RESULTS"
    puts "=" * 60

    results.each do |tier, passed|
      status = passed ? "✅ PASSED" : "❌ FAILED"
      puts "#{tier.capitalize.ljust(12)}: #{status}"
    end

    if @violations.any?
      puts "\n🚨 VIOLATIONS (#{@violations.size}):"
      @violations.each do |violation|
        severity_icon = violation[:severity] == :critical ? "🔴" : "🟠"
        puts "  #{severity_icon} [#{violation[:tier]}] #{violation[:message]}"
      end
    end

    if @warnings.any?
      puts "\n⚠️  WARNINGS (#{@warnings.size}):"
      @warnings.each do |warning|
        puts "  🟡 [#{warning[:tier]}] #{warning[:message]}"
      end
    end

    overall_status = results.values.all? && @violations.empty?

    puts "\n🎯 OVERALL STATUS: #{overall_status ? '✅ PASSED' : '❌ FAILED'}"

    if @policy["quality_gates"]["enforce_minimum"] && !overall_status
      puts "💥 Quality gate enforcement is enabled - build should fail!"
    end
  end

  def generate_readable_enforcement_summary(report)
    summary = <<~SUMMARY
      # Coverage Policy Enforcement Report

      **Generated**: #{report[:timestamp]}
      **Status**: #{report[:enforcement_summary][:status]}

      ## Summary
      - **Total Violations**: #{report[:enforcement_summary][:total_violations]}
      - **Critical Violations**: #{report[:enforcement_summary][:critical_violations]}
      - **Warnings**: #{report[:enforcement_summary][:total_warnings]}

    SUMMARY

    if report[:violations].any?
      summary += "## Violations\n\n"
      report[:violations].each do |violation|
        severity = violation[:severity] == :critical ? "🔴 CRITICAL" : "🟠 NORMAL"
        summary += "- **#{severity}** [#{violation[:tier]}]: #{violation[:message]}\n"
      end
      summary += "\n"
    end

    if report[:warnings].any?
      summary += "## Warnings\n\n"
      report[:warnings].each do |warning|
        summary += "- 🟡 [#{warning[:tier]}]: #{warning[:message]}\n"
      end
      summary += "\n"
    end

    File.write("coverage/POLICY_ENFORCEMENT.md", summary)
  end
end
