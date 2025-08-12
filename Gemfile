source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Email processing and parsing
gem "mail"
gem "net-imap"

# Authentication and API
gem "jwt"

# Rate limiting and security
gem "rack-attack"

# Date and text parsing
gem "chronic"

# CSV support for Ruby 3.4+
gem "csv"

# Charts and visualization
gem "chartkick"
gem "groupdate"

# Pagination
gem "kaminari"

# Bulk insert for performance
gem "activerecord-import"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Background job processing for broadcast reliability
gem "sidekiq"

# Concurrent programming support for batch collection
gem "concurrent-ruby"

# Redis connection pooling for analytics
gem "connection_pool"
gem "redis"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Test data factories
  gem "factory_bot_rails"

  # Spring preloader for faster test startup
  gem "spring"
  gem "spring-commands-rspec"

  # Performance testing and profiling
  gem "memory_profiler"
  gem "benchmark-ips"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Modern browser automation with Chrome DevTools Protocol
  gem "cuprite"

  # External HTTP request mocking for IMAP and API testing
  gem "webmock"
  gem "vcr"

  # Parallel test execution
  gem "parallel_tests"

  # Performance and benchmarking
  gem "rspec-benchmark"

  # JSON response testing
  gem "json_spec"

  # Database cleaning strategies
  gem "database_cleaner-active_record"

  # ActionCable testing support
  gem "action-cable-testing"

  # Enhanced collection matchers
  gem "rspec-collection_matchers"

  # Background job testing utilities
  gem "rspec-sidekiq" # Will adapt for Solid Queue
end

gem "rspec-rails", "~> 8.0"

gem "simplecov", "~> 0.22.0", group: :test

gem "shoulda-matchers", "~> 6.5", group: :test
gem "rails-controller-testing", group: :test

gem "rails_best_practices", "~> 1.23", group: :development

# Categorization improvement dependencies
group :categorization do
  gem "fuzzy-string-match", "~> 1.0"
  gem "redis-namespace", "~> 1.10"
  gem "hiredis", "~> 0.6"
  # concurrent-ruby and connection_pool already defined above
end
