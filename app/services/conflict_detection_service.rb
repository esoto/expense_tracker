class ConflictDetectionService
  attr_reader :sync_session, :errors, :metrics_collector

  DUPLICATE_THRESHOLD = 90.0 # 90% similarity = duplicate
  SIMILAR_THRESHOLD = 70.0   # 70% similarity = similar

  def initialize(sync_session, metrics_collector: nil)
    @sync_session = sync_session
    @metrics_collector = metrics_collector
    @errors = []
  end

  def detect_conflict_for_expense(new_expense_data)
    if @metrics_collector
      email_account = EmailAccount.find_by(id: new_expense_data[:email_account_id])
      @metrics_collector.track_operation(:detect_conflicts, email_account) do
        perform_conflict_detection(new_expense_data)
      end
    else
      perform_conflict_detection(new_expense_data)
    end
  end

  def perform_conflict_detection(new_expense_data)
    # Find potential duplicates based on key fields
    candidates = find_candidate_expenses(new_expense_data)
    return nil if candidates.empty?

    # Calculate similarity scores and find best match
    best_match = nil
    highest_score = 0.0

    candidates.each do |existing_expense|
      score = calculate_similarity(existing_expense, new_expense_data)

      if score > highest_score
        highest_score = score
        best_match = existing_expense
      end
    end

    return nil unless best_match && highest_score >= SIMILAR_THRESHOLD

    # Determine conflict type
    conflict_type = determine_conflict_type(highest_score, best_match, new_expense_data)

    # Calculate differences
    differences = calculate_differences(best_match, new_expense_data)

    # Create conflict record
    create_conflict(
      existing_expense: best_match,
      new_expense_data: new_expense_data,
      conflict_type: conflict_type,
      similarity_score: highest_score,
      differences: differences
    )
  end

  def detect_conflicts_batch(new_expenses_data)
    conflicts = []

    new_expenses_data.each do |expense_data|
      conflict = detect_conflict_for_expense(expense_data)
      conflicts << conflict if conflict
    end

    conflicts
  end

  def auto_resolve_obvious_duplicates
    resolved_count = 0

    # Find high-confidence duplicates
    high_confidence_duplicates = sync_session.sync_conflicts
      .unresolved
      .where("similarity_score >= ?", 95.0)
      .where(conflict_type: "duplicate")

    high_confidence_duplicates.find_each do |conflict|
      begin
        # Auto-resolve by keeping existing
        conflict.resolve!("keep_existing", {}, "system_auto")
        resolved_count += 1

        Rails.logger.info "[ConflictDetection] Auto-resolved duplicate conflict ##{conflict.id}"
      rescue => e
        Rails.logger.error "[ConflictDetection] Failed to auto-resolve conflict ##{conflict.id}: #{e.message}"
        add_error("Failed to auto-resolve conflict ##{conflict.id}")
      end
    end

    resolved_count
  end

  private

  def find_candidate_expenses(new_expense_data)
    # Build query to find potential matches
    scope = Expense.where(status: [ :processed, :pending ])

    # Must be from same account
    if new_expense_data[:email_account_id]
      scope = scope.where(email_account_id: new_expense_data[:email_account_id])
    end

    # Look for expenses within date range (±3 days)
    if new_expense_data[:transaction_date]
      date = new_expense_data[:transaction_date]
      scope = scope.where(transaction_date: (date - 3.days)..(date + 3.days))
    end

    # Look for similar amounts (±10%)
    if new_expense_data[:amount]
      amount = new_expense_data[:amount].to_f
      min_amount = amount * 0.9
      max_amount = amount * 1.1
      scope = scope.where(amount: min_amount..max_amount)
    end

    # Limit to reasonable number of candidates
    scope.limit(20)
  end

  def calculate_similarity(existing_expense, new_expense_data)
    score = 0.0
    weights = {
      amount: 35.0,
      date: 25.0,
      merchant: 20.0,
      description: 10.0,
      currency: 10.0
    }

    # Amount similarity (exact match = 100%, within 1% = 90%, within 5% = 70%, etc.)
    if new_expense_data[:amount]
      amount_diff = (existing_expense.amount - new_expense_data[:amount].to_f).abs
      amount_ratio = amount_diff / existing_expense.amount

      amount_score = if amount_ratio == 0
        100
      elsif amount_ratio <= 0.01
        90
      elsif amount_ratio <= 0.05
        70
      elsif amount_ratio <= 0.10
        50
      else
        0
      end

      score += (amount_score * weights[:amount] / 100.0)
    end

    # Date similarity (same day = 100%, 1 day diff = 80%, 2 days = 60%, 3 days = 40%)
    if new_expense_data[:transaction_date]
      existing_date = existing_expense.transaction_date.to_date
      new_date = new_expense_data[:transaction_date].to_date
      days_diff = (existing_date - new_date).to_i.abs

      date_score = case days_diff
      when 0 then 100
      when 1 then 80
      when 2 then 60
      when 3 then 40
      else 0
      end

      score += (date_score * weights[:date] / 100.0)
    end

    # Merchant similarity (fuzzy match)
    if new_expense_data[:merchant_name]
      merchant_score = string_similarity(
        existing_expense.merchant_name.to_s.downcase,
        new_expense_data[:merchant_name].to_s.downcase
      )
      score += (merchant_score * weights[:merchant] / 100.0)
    end

    # Description similarity
    if new_expense_data[:description]
      desc_score = string_similarity(
        existing_expense.description.to_s.downcase,
        new_expense_data[:description].to_s.downcase
      )
      score += (desc_score * weights[:description] / 100.0)
    end

    # Currency match
    if new_expense_data[:currency]
      # Convert string to symbol for enum comparison
      currency_score = existing_expense.currency.to_s == new_expense_data[:currency].to_s ? 100 : 0
      score += (currency_score * weights[:currency] / 100.0)
    end

    score
  end

  def string_similarity(str1, str2)
    return 100.0 if str1 == str2
    return 0.0 if str1.empty? || str2.empty?

    # Simple character-based similarity
    # In production, consider using Levenshtein distance or other algorithms
    longer = [ str1.length, str2.length ].max
    edit_distance = levenshtein_distance(str1, str2)

    ((longer - edit_distance) * 100.0 / longer).round(2)
  end

  def levenshtein_distance(str1, str2)
    # Simple Levenshtein distance implementation
    m = str1.length
    n = str2.length

    return n if m == 0
    return m if n == 0

    # Create distance matrix
    d = Array.new(m + 1) { Array.new(n + 1) }

    (0..m).each { |i| d[i][0] = i }
    (0..n).each { |j| d[0][j] = j }

    (1..n).each do |j|
      (1..m).each do |i|
        cost = str1[i - 1] == str2[j - 1] ? 0 : 1
        d[i][j] = [
          d[i - 1][j] + 1,      # deletion
          d[i][j - 1] + 1,      # insertion
          d[i - 1][j - 1] + cost # substitution
        ].min
      end
    end

    d[m][n]
  end

  def determine_conflict_type(score, existing_expense, new_expense_data)
    if score >= DUPLICATE_THRESHOLD
      "duplicate"
    elsif score >= SIMILAR_THRESHOLD
      "similar"
    elsif existing_expense.raw_email_content != new_expense_data[:raw_email_content]
      "updated"
    else
      "needs_review"
    end
  end

  def calculate_differences(existing_expense, new_expense_data)
    differences = {}

    # Compare key fields
    fields_to_compare = %w[amount transaction_date merchant_name description currency category_id]

    fields_to_compare.each do |field|
      existing_value = existing_expense.send(field)
      new_value = new_expense_data[field.to_sym]

      if existing_value != new_value
        differences[field] = {
          existing: existing_value,
          new: new_value,
          match: false
        }
      else
        differences[field] = {
          existing: existing_value,
          new: new_value,
          match: true
        }
      end
    end

    differences
  end

  def create_conflict(existing_expense:, new_expense_data:, conflict_type:, similarity_score:, differences:)
    # Create temporary expense for new data (will be saved if resolution keeps it)
    # Ensure all required fields are present
    expense_attrs = new_expense_data.merge(
      status: "duplicate",
      currency: new_expense_data[:currency] || "crc"
    )

    new_expense = Expense.new(expense_attrs)
    new_expense.save! if conflict_type == "duplicate" || conflict_type == "similar"

    conflict = sync_session.sync_conflicts.create!(
      existing_expense: existing_expense,
      new_expense: new_expense,
      conflict_type: conflict_type,
      similarity_score: similarity_score,
      differences: differences,
      conflict_data: {
        detection_timestamp: Time.current,
        detection_method: "automatic",
        algorithm_version: "1.0"
      }
    )

    # Broadcast conflict detection
    broadcast_conflict_detected(conflict)

    conflict
  rescue => e
    Rails.logger.error "[ConflictDetection] Failed to create conflict: #{e.message}"
    add_error("Failed to create conflict: #{e.message}")
    nil
  end

  def broadcast_conflict_detected(conflict)
    SyncStatusChannel.broadcast_to(
      sync_session,
      {
        event: "conflict_detected",
        conflict: {
          id: conflict.id,
          type: conflict.conflict_type,
          similarity_score: conflict.similarity_score,
          existing_expense_id: conflict.existing_expense_id,
          new_expense_id: conflict.new_expense_id
        }
      }
    )
  end

  def add_error(message)
    @errors << message
  end
end
