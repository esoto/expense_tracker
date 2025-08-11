# frozen_string_literal: true

# Helper for testing migrations
module MigrationHelper
  # Requires a migration file from db/migrate directory
  # Usage: require_migration "create_categorization_pattern_tables"
  def require_migration(migration_name)
    migration_file = Dir[Rails.root.join("db/migrate/*_#{migration_name}.rb")].first

    if migration_file.nil?
      raise ArgumentError, "Migration file not found: #{migration_name}"
    end

    require migration_file

    # Extract the class name from the migration file
    migration_class_name = File.basename(migration_file, ".rb").sub(/^\d+_/, "").camelize

    # Return the migration class
    migration_class_name.constantize
  end
end

# Include the helper in RSpec configuration
RSpec.configure do |config|
  config.include MigrationHelper, type: :migration
end
