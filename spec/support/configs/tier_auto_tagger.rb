# frozen_string_literal: true

# Intelligent automatic test tier detection and tagging
# This module analyzes test files and automatically assigns appropriate tier tags

module TierAutoTagger
  # Patterns for identifying test tiers based on file paths and names
  TIER_PATTERNS = {
    performance: [
      /performance/i,
      /benchmark/i,
      /load_test/i,
      /stress/i,
      /_perf_spec\.rb$/,
      /spec\/performance\//
    ],
    integration: [
      /integration/i,
      /orchestrator/i,
      /workflow/i,
      /end_to_end/i,
      /e2e/i,
      /_integration_spec\.rb$/,
      /spec\/requests\//,
      /spec\/channels\//,
      /spec\/jobs\//
    ],
    system: [
      /spec\/system\//,
      /capybara/i,
      /browser/i,
      /selenium/i,
      /_system_spec\.rb$/
    ]
  }.freeze

  # Content patterns that indicate test complexity
  CONTENT_INDICATORS = {
    integration: [
      /describe.*Integration/i,
      /context.*integration/i,
      /it.*end.?to.?end/i,
      /multiple.*services/i,
      /workflow/i,
      /orchestrat/i
    ],
    performance: [
      /benchmark/i,
      /performance/i,
      /\.measure/,
      /Benchmark\./,
      /time.*expect/i,
      /milliseconds?/i,
      /seconds?.*expect/i,
      /faster.*than/i,
      /\.profile/
    ]
  }.freeze

  class << self
    # Analyzes a spec file and returns the recommended tier
    def analyze_file(file_path)
      return :system if system_test?(file_path)
      return :performance if performance_test?(file_path)
      return :integration if integration_test?(file_path)

      # Read file content for deeper analysis
      content = File.read(file_path) if File.exist?(file_path)
      return analyze_content(content, file_path) if content

      :unit # Default to unit test
    rescue => e
      Rails.logger.warn("Failed to analyze #{file_path}: #{e.message}")
      :unit
    end

    # Analyzes file content for tier indicators
    def analyze_content(content, file_path = nil)
      # Check for performance indicators first (most specific)
      if performance_content?(content)
        return :performance
      end

      # Check for integration indicators
      if integration_content?(content)
        return :integration
      end

      # Check for unit test anti-patterns (things that make it not a unit test)
      if complex_setup?(content)
        return :integration
      end

      :unit
    end

    # Tags a spec file with the appropriate RSpec metadata
    def tag_file!(file_path)
      return unless File.exist?(file_path)

      tier = analyze_file(file_path)
      content = File.read(file_path)

      # Skip if already has tier tags
      return tier if has_tier_tags?(content)

      # Add tag to the first describe block
      updated_content = add_tier_tag(content, tier)

      if updated_content != content
        File.write(file_path, updated_content)
        puts "Tagged #{file_path} as :#{tier}"
      end

      tier
    end

    private

    def system_test?(file_path)
      TIER_PATTERNS[:system].any? { |pattern| file_path.match?(pattern) }
    end

    def performance_test?(file_path)
      TIER_PATTERNS[:performance].any? { |pattern| file_path.match?(pattern) }
    end

    def integration_test?(file_path)
      TIER_PATTERNS[:integration].any? { |pattern| file_path.match?(pattern) }
    end

    def performance_content?(content)
      CONTENT_INDICATORS[:performance].any? { |pattern| content.match?(pattern) }
    end

    def integration_content?(content)
      # Check for multiple service interactions
      service_count = content.scan(/\.new\(|\.call|\.perform/).length
      return true if service_count > 5

      # Check for database operations across multiple models
      model_operations = content.scan(/\.create|\.update|\.destroy|\.find/).length
      return true if model_operations > 3

      # Check for explicit integration patterns
      CONTENT_INDICATORS[:integration].any? { |pattern| content.match?(pattern) }
    end

    def complex_setup?(content)
      # Check for complex setup that indicates integration test
      setup_complexity = [
        content.scan(/before.*do/).length,
        content.scan(/let!/).length * 2, # let! is more expensive
        content.scan(/create\(/).length,
        content.scan(/FactoryBot/).length
      ].sum

      setup_complexity > 5
    end

    def has_tier_tags?(content)
      content.match?(/:unit|:integration|:performance|:system/)
    end

    def add_tier_tag(content, tier)
      # Find the first describe block and add the tier tag
      content.gsub(/^(\s*)(RSpec\.describe|describe)\s+(.+?)\s+do\s*$/) do |match|
        indent = $1
        describe_keyword = $2
        description = $3

        # Check if there are already hash-style metadata
        if description.include?(',') && (description.include?('type:') || description.include?(':'))
          # Add as hash key
          "#{indent}#{describe_keyword} #{description}, #{tier}: true do"
        else
          # Add as symbol
          "#{indent}#{describe_keyword} #{description}, :#{tier} do"
        end
      end
    end
  end
end
