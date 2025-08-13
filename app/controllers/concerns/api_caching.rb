# frozen_string_literal: true

module ApiCaching
  extend ActiveSupport::Concern

  included do
    # Set cache headers for GET requests (excluding HEAD)
    def set_cache_headers(max_age: 300, public: true, must_revalidate: true)
      return unless request.get? && !request.head?

      if public
        expires_in max_age.seconds, public: true, must_revalidate: must_revalidate
      else
        expires_in max_age.seconds, private: true, must_revalidate: must_revalidate
      end
    end

    # Set ETag and handle conditional GET (excluding HEAD)
    def handle_conditional_get(resource)
      return unless request.get? && !request.head?

      if resource.respond_to?(:cache_key_with_version)
        fresh_when(resource, public: true)
      elsif resource.respond_to?(:maximum)
        # For collections
        fresh_when(
          etag: generate_collection_etag(resource),
          last_modified: resource.maximum(:updated_at),
          public: true
        )
      end
    end

    # Generate ETag for collections
    def generate_collection_etag(collection)
      if collection.respond_to?(:cache_key_with_version)
        collection.cache_key_with_version
      else
        # Fallback for collections without cache_key
        ids = collection.pluck(:id).join("-")
        max_updated = collection.maximum(:updated_at)
        "collection-#{ids}-#{max_updated&.to_i}"
      end
    end

    # Disable caching for sensitive endpoints
    def disable_cache
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "0"
    end
  end
end
