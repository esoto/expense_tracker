# frozen_string_literal: true

# Aggressive optimizations for unit tests to achieve <30 second execution time
# These optimizations should only be applied to tests tagged as :unit

RSpec.configure do |config|
  # Unit test optimizations - only apply to :unit tagged tests
  config.before(:suite) do
    next unless RSpec.configuration.inclusion_filter[:unit]
    # Disable unnecessary Rails components for unit tests
    if defined?(Rails)
      # Disable action mailer deliveries
      ActionMailer::Base.delivery_method = :test
      ActionMailer::Base.perform_deliveries = false

      # Disable active job queue processing
      ActiveJob::Base.queue_adapter = :test

      # Disable broadcasting in unit tests
      ActionCable.server.config.disable_request_forgery_protection = true if defined?(ActionCable)
    end

    # Set test-specific configurations
    Rails.application.config.cache_store = :null_store if defined?(Rails)

    # Disable external service calls
    if defined?(WebMock)
      WebMock.enable!
      WebMock.disable_net_connect!(allow_localhost: true)
    end
  end

  config.around(:each, :unit) do |example|
    # Use Rails' built-in transactional fixtures for unit tests
    # This is much faster and avoids manual transaction management conflicts
    if defined?(ActiveRecord) && RSpec.configuration.use_transactional_fixtures
      # Let Rails handle the transaction - don't manually manage it
      example.run
    else
      # Only manually manage transactions if transactional fixtures are disabled
      if defined?(ActiveRecord)
        ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
          example.run
          raise ActiveRecord::Rollback
        end
      else
        example.run
      end
    end
  end

  config.before(:each, :unit) do
    # Clear any cached data before each unit test
    Rails.cache.clear if defined?(Rails) && Rails.respond_to?(:cache)

    # Reset any service state
    # (CachedCategorizationService removed - no longer needed)

    # Stub external services by default
    stub_external_services if respond_to?(:stub_external_services)
  end

  # Performance optimizations for unit tests
  config.before(:suite) do
    next unless RSpec.configuration.inclusion_filter[:unit]
    # Reduce garbage collection frequency during unit tests
    if RUBY_ENGINE == 'ruby'
      GC.disable

      # Re-enable GC after unit tests
      RSpec.configuration.after(:suite) do
        next unless RSpec.configuration.inclusion_filter[:unit]
        GC.enable
        GC.start
      end
    end

    # Preload commonly used classes to avoid autoloading overhead
    UnitTestOptimizations.preload_common_classes
  end

  # Parallel execution support for unit tests (if available)
  if defined?(ParallelTests)
    config.before(:suite) do
      next unless RSpec.configuration.inclusion_filter[:unit]
      # Setup parallel test database if needed
      # DISABLED: Causing socket errors with Ruby 3.4
      # if ParallelTests.first_process?
      #   puts "Setting up parallel unit test execution..."
      # end
    end
  end
end

# Module for unit test optimization utilities
module UnitTestOptimizations
  def self.preload_common_classes
    # Preload commonly used classes to reduce autoloading overhead
    return unless defined?(Rails)

    # Skip eager loading that can cause issues in tests
    # Rails.application.eager_load! if Rails.env.test?

    # Preload common service classes
    common_classes = [
      'Services::Categorization::EnhancedCategorizationService',
      'Services::ExpenseFilterService',
      'Services::Email::ProcessingService'
    ]

    common_classes.each do |class_name|
      begin
        class_name.constantize
      rescue NameError
        # Class doesn't exist, skip
      end
    end
  end

  def self.stub_external_services
    # Stub common external services to prevent network calls in unit tests
    if defined?(WebMock)
      # Stub any HTTP requests
      WebMock.stub_request(:any, /.*/).to_return(status: 200, body: '{}')
    end

    # Stub Rails services
    if defined?(ActionMailer)
      allow(ActionMailer::Base).to receive(:deliver_now)
      allow(ActionMailer::Base).to receive(:deliver_later)
    end

    # Stub background jobs
    if defined?(ActiveJob)
      allow_any_instance_of(ActiveJob::Base).to receive(:perform_later)
      allow_any_instance_of(ActiveJob::Base).to receive(:perform_now)
    end

    # Stub file system operations
    allow(File).to receive(:write)
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:rm_rf)
  end
end

# Helper methods for unit test optimization
module UnitTestHelpers
  # Use build_stubbed instead of create for faster tests
  def quick_build(factory_name, attributes = {})
    if defined?(FactoryBot)
      FactoryBot.build_stubbed(factory_name, attributes)
    else
      build_stubbed(factory_name, attributes)
    end
  end

  # Create minimal test doubles
  def minimal_double(class_name, methods = {})
    instance_double(class_name, methods)
  end

  # Skip expensive setup in unit tests
  def skip_expensive_setup
    # Skip database seeds
    allow(Rails.application).to receive(:load_seed) if defined?(Rails)

    # Skip asset precompilation
    allow_any_instance_of(ActionView::Base).to receive(:asset_path) { |path| path }
  end
end

RSpec.configure do |config|
  config.include UnitTestHelpers, :unit
end
