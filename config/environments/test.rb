# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  #
  # Workaround for Rails 8.0 + Ruby 3.4 FrozenError in CI environments
  # Disable eager loading to prevent autoloader paths modification
  config.eager_load = false

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :memory_store, { size: 32.megabytes }

  # ActiveJob configuration for testing
  config.active_job.queue_adapter = :test

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Silence database logs in tests to reduce noise
  config.log_level = :warn
  config.active_record.logger = nil

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Configure Active Record encryption for test environment with performance optimization
  # Use simple static keys for faster test performance instead of pulling from credentials
  config.active_record.encryption.primary_key = "test_primary_key_12345678901234567890123456"
  config.active_record.encryption.deterministic_key = "test_deterministic_key_123456789012345678901"
  config.active_record.encryption.key_derivation_salt = "test_salt_123456789012345678901234567890123456"

  # Optimize encryption for test performance
  config.active_record.encryption.hash_digest_class = OpenSSL::Digest::SHA1  # Faster than SHA256
  config.active_record.encryption.support_sha1_for_non_deterministic_encryption = true
end
