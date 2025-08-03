class EmailFetcherResponse
  attr_reader :success, :errors, :processed_emails_count, :total_emails_found

  def initialize(success: false, errors: [], processed_emails_count: 0, total_emails_found: 0)
    @success = success
    @errors = Array(errors)
    @processed_emails_count = processed_emails_count
    @total_emails_found = total_emails_found
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def has_errors?
    @errors.any?
  end

  def error_messages
    @errors.join(", ")
  end

  def to_h
    {
      success: @success,
      errors: @errors,
      processed_emails_count: @processed_emails_count,
      total_emails_found: @total_emails_found
    }
  end

  def self.success(processed_emails_count: 0, total_emails_found: 0, errors: [])
    new(
      success: true,
      processed_emails_count: processed_emails_count,
      total_emails_found: total_emails_found,
      errors: errors
    )
  end

  def self.failure(errors:, processed_emails_count: 0, total_emails_found: 0)
    new(
      success: false,
      errors: errors,
      processed_emails_count: processed_emails_count,
      total_emails_found: total_emails_found
    )
  end
end
