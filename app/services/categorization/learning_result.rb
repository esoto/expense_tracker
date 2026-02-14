# frozen_string_literal: true

module Services::Categorization
  # Value object representing the result of a learning operation
  # Tracks patterns created/updated and any errors that occurred
  class LearningResult
    attr_reader :success, :patterns_created, :patterns_updated,
                :message, :metadata, :processing_time_ms

    def initialize(
      success:,
      patterns_created: 0,
      patterns_updated: 0,
      message: nil,
      metadata: {},
      processing_time_ms: 0.0
    )
      @success = success
      @patterns_created = patterns_created
      @patterns_updated = patterns_updated
      @message = message
      @metadata = metadata
      @processing_time_ms = processing_time_ms
      @created_at = Time.current
    end

    # Factory methods

    def self.success(patterns_created: 0, patterns_updated: 0, message: nil, metadata: {})
      new(
        success: true,
        patterns_created: patterns_created,
        patterns_updated: patterns_updated,
        message: message || "Learning completed successfully",
        metadata: metadata
      )
    end

    def self.error(message, metadata: {})
      new(
        success: false,
        message: message,
        metadata: metadata.merge(error: true)
      )
    end

    # Query methods

    def success?
      @success
    end

    def failure?
      !@success
    end

    def error
      @message unless @success
    end

    def patterns_affected
      @patterns_created + @patterns_updated
    end

    def any_patterns_created?
      @patterns_created > 0
    end

    def any_patterns_updated?
      @patterns_updated > 0
    end

    # Export methods

    def to_h
      {
        success: @success,
        patterns_created: @patterns_created,
        patterns_updated: @patterns_updated,
        patterns_affected: patterns_affected,
        message: @message,
        processing_time_ms: @processing_time_ms.round(3),
        metadata: @metadata,
        created_at: @created_at
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Display methods

    def to_s
      if success?
        "Learning successful: #{patterns_affected} patterns affected"
      else
        "Learning failed: #{@message}"
      end
    end

    def inspect
      "#<LearningResult success=#{@success} created=#{@patterns_created} " \
        "updated=#{@patterns_updated} message=\"#{@message}\">"
    end
  end
end
