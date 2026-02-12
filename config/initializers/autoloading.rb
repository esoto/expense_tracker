# frozen_string_literal: true

# Configure Services namespace for app/services directory
# This allows using Services::Email::ProcessingService, Services::BulkCategorization::BatchProcessor, etc.
# instead of Email::ProcessingService, BulkCategorization::BatchProcessor
#
# Rails by default treats app/services as a root namespace (like app/models),
# but we want a Services:: prefix for better organization and to avoid naming conflicts.
#
# See: https://guides.rubyonrails.org/autoloading_and_reloading_constants.html#customizing-inflections

# Define the Services module
module Services; end

# Configure Zeitwerk to namespace app/services under Services module
Rails.autoloaders.main.push_dir(
  Rails.root.join("app/services").to_s,
  namespace: Services
)
