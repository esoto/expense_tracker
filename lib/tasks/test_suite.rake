namespace :test do
  desc "Run all unit tests (fast, <30s)"
  task :unit do
    sh "bin/test-unit"
  end
  
  desc "Run integration tests"
  task :integration do
    sh "bin/test-integration"
  end
  
  desc "Run performance tests"
  task :performance do
    sh "bin/test-performance"
  end
  
  desc "Run system/browser tests"
  task :system do
    sh "bundle exec rspec spec/system"
  end
  
  desc "Run tests in watch mode"
  task :watch do
    sh "bin/test-watch"
  end
  
  desc "Run full test suite (CI mode)"
  task :ci => :environment do
    ENV['CI'] = 'true'
    ENV['RUN_ALL_TESTS'] = 'true'
    
    puts "\n🔨 Running full CI test suite...\n"
    
    suites = [
      { name: "Unit Tests", command: "bin/test-unit" },
      { name: "Integration Tests", command: "bin/test-integration" },
      { name: "System Tests", command: "bundle exec rspec spec/system" },
      { name: "Performance Tests", command: "bin/test-performance" }
    ]
    
    results = {}
    
    suites.each do |suite|
      puts "\n" + "="*60
      puts "Running #{suite[:name]}"
      puts "="*60 + "\n"
      
      start_time = Time.now
      success = system(suite[:command])
      elapsed = Time.now - start_time
      
      results[suite[:name]] = {
        success: success,
        time: elapsed
      }
      
      unless success
        puts "\n❌ #{suite[:name]} failed!"
        break
      end
    end
    
    # Print summary
    puts "\n" + "="*60
    puts "TEST SUITE SUMMARY"
    puts "="*60
    
    results.each do |name, result|
      status = result[:success] ? "✅" : "❌"
      time = (result[:time] / 60).round(2)
      puts "#{status} #{name}: #{time} minutes"
    end
    
    total_time = results.values.sum { |r| r[:time] }
    puts "\nTotal time: #{(total_time / 60).round(2)} minutes"
    
    # Exit with failure if any suite failed
    exit 1 unless results.values.all? { |r| r[:success] }
  end
  
  desc "Run focused development tests (unit + modified files)"
  task :dev do
    # Get modified files from git
    changed_files = `git diff --name-only HEAD`.split("\n")
    spec_files = changed_files.select { |f| f.end_with?('_spec.rb') }
    
    if spec_files.any?
      puts "Running tests for modified files..."
      sh "bundle exec rspec #{spec_files.join(' ')}"
    else
      puts "No modified spec files. Running unit tests..."
      sh "bin/test-unit"
    end
  end
  
  desc "Generate test coverage report"
  task :coverage => :environment do
    ENV['COVERAGE'] = 'true'
    sh "bundle exec rspec"
  end
  
  desc "Profile test suite performance"
  task :profile => :environment do
    ENV['PROFILE'] = 'true'
    sh "bundle exec rspec --profile 50"
  end
end

# Override default test task
task :test => 'test:unit'