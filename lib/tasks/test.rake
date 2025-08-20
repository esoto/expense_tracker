# frozen_string_literal: true

namespace :test do
  desc "Run fast unit tests only"
  task unit: :environment do
    puts "🧪 Running unit tests..."
    system("bin/test-unit")
  end

  desc "Run integration tests"
  task integration: :environment do
    puts "🔗 Running integration tests..."
    system("bin/test-integration")
  end

  desc "Run performance tests"
  task performance: :environment do
    puts "⚡ Running performance tests..."
    system("bin/test-performance")
  end

  desc "Run system tests"
  task system: :environment do
    puts "🌐 Running system tests..."
    system("bin/test-system")
  end

  desc "Run all tests for CI/CD"
  task ci: :environment do
    puts "🚀 Running full test suite for CI/CD..."

    # Run in order of speed for fail-fast
    tasks = %w[unit integration system performance]

    tasks.each do |task_name|
      puts "\n" + "="*50
      puts "Running #{task_name} tests..."
      puts "="*50

      result = system("rails test:#{task_name}")
      unless result
        puts "\n❌ #{task_name.capitalize} tests failed!"
        exit 1
      end
    end

    puts "\n✅ All tests passed in CI/CD!"
  end

  desc "Analyze test distribution and performance"
  task analyze: :environment do
    puts "📊 Analyzing test suite..."

    # Count tests by category
    system("find spec -name '*_spec.rb' | wc -l | xargs echo 'Total spec files:'")
    system("find spec/models -name '*_spec.rb' | wc -l | xargs echo 'Model specs:'")
    system("find spec/controllers -name '*_spec.rb' | wc -l | xargs echo 'Controller specs:'")
    system("find spec/services -name '*_spec.rb' | wc -l | xargs echo 'Service specs:'")
    system("find spec/requests -name '*_spec.rb' | wc -l | xargs echo 'Request specs:'")
    system("find spec/system -name '*_spec.rb' | wc -l | xargs echo 'System specs:'")

    puts "\n📈 Running test performance analysis..."
    system("bundle exec rspec --dry-run --format json | jq '.examples | length' 2>/dev/null || echo 'Install jq for detailed analysis'")
  end

  desc "Profile slow tests"
  task profile: :environment do
    puts "🐌 Profiling slow tests..."
    system("bundle exec rspec --profile 20 --format progress")
  end

  desc "Run tests for modified files only"
  task dev: :environment do
    puts "🔄 Running tests for modified files..."

    # Get list of modified files
    modified_files = `git diff --name-only HEAD~1..HEAD | grep -E '\\.(rb)$'`.split("\n")

    if modified_files.empty?
      puts "No modified Ruby files found. Running unit tests instead."
      system("bin/test-unit")
    else
      # Convert app files to spec files
      spec_files = modified_files.map do |file|
        if file.start_with?("app/")
          file.gsub("app/", "spec/").gsub(".rb", "_spec.rb")
        elsif file.start_with?("spec/")
          file
        end
      end.compact.select { |file| File.exist?(file) }

      if spec_files.any?
        puts "Testing files: #{spec_files.join(', ')}"
        system("bundle exec rspec #{spec_files.join(' ')} --format documentation")
      else
        puts "No corresponding spec files found. Running unit tests."
        system("bin/test-unit")
      end
    end
  end

  desc "Generate test coverage report"
  task coverage: :environment do
    puts "📋 Generating test coverage report..."
    ENV["COVERAGE"] = "true"
    system("bundle exec rspec")
    puts "\nCoverage report generated in coverage/"
  end
end
