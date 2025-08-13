# frozen_string_literal: true

module ApiConfiguration
  extend ActiveSupport::Concern

  # Pagination constants
  DEFAULT_PAGE_SIZE = 25
  MAX_PAGE_SIZE = 100
  MIN_PAGE_SIZE = 1

  # Cache expiration times
  CACHE_EXPIRY_SHORT = 1.minute
  CACHE_EXPIRY_MEDIUM = 5.minutes
  CACHE_EXPIRY_LONG = 1.hour
  CACHE_EXPIRY_READ = 15.minutes

  # Rate limiting constants
  RATE_LIMIT_WINDOW = 1.hour
  RATE_LIMIT_MAX_REQUESTS = 1000

  # API versioning
  CURRENT_API_VERSION = "v1"
  SUPPORTED_API_VERSIONS = [ "v1" ].freeze

  # Performance thresholds
  MIN_SUCCESS_RATE_THRESHOLD = 0.0
  MAX_SUCCESS_RATE_THRESHOLD = 1.0
  DEFAULT_CONFIDENCE_WEIGHT = 1.0
  COMPOSITE_CONFIDENCE_WEIGHT = 1.5

  # Security
  TOKEN_CACHE_KEY_LENGTH = 16
  SECURE_TOKEN_LENGTH = 32

  included do
    # Make constants available as instance methods
    def api_config
      {
        pagination: {
          default_size: DEFAULT_PAGE_SIZE,
          max_size: MAX_PAGE_SIZE,
          min_size: MIN_PAGE_SIZE
        },
        cache: {
          short: CACHE_EXPIRY_SHORT,
          medium: CACHE_EXPIRY_MEDIUM,
          long: CACHE_EXPIRY_LONG,
          read: CACHE_EXPIRY_READ
        },
        rate_limit: {
          window: RATE_LIMIT_WINDOW,
          max_requests: RATE_LIMIT_MAX_REQUESTS
        },
        version: {
          current: CURRENT_API_VERSION,
          supported: SUPPORTED_API_VERSIONS
        }
      }
    end

    def paginate_with_limits(collection)
      page_size = params[:per_page].to_i
      page_size = DEFAULT_PAGE_SIZE if page_size <= 0
      page_size = [ page_size, MAX_PAGE_SIZE ].min
      page_size = [ page_size, MIN_PAGE_SIZE ].max

      collection.page(params[:page]).per(page_size)
    end
  end
end
