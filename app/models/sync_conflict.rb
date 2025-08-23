class SyncConflict < ApplicationRecord
  # Associations
  belongs_to :existing_expense, class_name: "Expense"
  belongs_to :new_expense, class_name: "Expense", optional: true
  belongs_to :sync_session
  has_many :conflict_resolutions, dependent: :destroy

  # Enums
  enum :conflict_type, {
    duplicate: "duplicate",
    similar: "similar",
    updated: "updated",
    needs_review: "needs_review"
  }, prefix: true

  enum :status, {
    pending: "pending",
    resolved: "resolved",
    ignored: "ignored",
    auto_resolved: "auto_resolved"
  }, prefix: true

  enum :resolution_action, {
    keep_existing: "keep_existing",
    keep_new: "keep_new",
    keep_both: "keep_both",
    merged: "merged",
    custom: "custom"
  }, prefix: true, allow_nil: true

  # Validations
  validates :conflict_type, presence: true
  validates :status, presence: true
  validates :similarity_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :priority, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :unresolved, -> { where(status: [ "pending" ]) }
  scope :resolved, -> { where(status: [ "resolved", "auto_resolved" ]) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :bulk_resolvable, -> { where(bulk_resolvable: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_session, ->(session_id) { where(sync_session_id: session_id) }
  scope :with_expenses, -> { includes(:existing_expense, :new_expense) }

  # Callbacks
  before_validation :calculate_similarity_score, if: :should_calculate_similarity?
  before_validation :set_priority
  after_update :broadcast_resolution, if: :saved_change_to_status?

  # Instance methods
  def resolve!(action, resolution_data = {}, resolved_by = nil)
    transaction do
      # Create resolution record
      resolution = conflict_resolutions.create!(
        action: action,
        before_state: capture_current_state,
        resolution_method: "manual",
        resolved_by: resolved_by
      )

      # Apply resolution
      apply_resolution(action, resolution_data)

      # Update resolution record with after state
      resolution.update!(
        after_state: capture_current_state,
        changes_made: calculate_changes(resolution.before_state)
      )

      # Update conflict status
      update!(
        status: "resolved",
        resolution_action: action,
        resolution_data: resolution_data,
        resolved_at: Time.current,
        resolved_by: resolved_by
      )

      resolution
    end
  end

  def undo_last_resolution!
    last_resolution = conflict_resolutions.where(undone: false).order(created_at: :desc).first
    return false unless last_resolution&.undoable

    transaction do
      # Create undo resolution
      undo_resolution = conflict_resolutions.create!(
        action: "undo",
        before_state: capture_current_state,
        resolution_method: "manual"
      )

      # Restore previous state
      restore_state(last_resolution.before_state)

      # Mark original resolution as undone
      last_resolution.update!(
        undone: true,
        undone_at: Time.current,
        undone_by_resolution: undo_resolution
      )

      # Update conflict status
      update!(
        status: "pending",
        resolution_action: nil,
        resolution_data: {},
        resolved_at: nil
      )

      undo_resolution
    end
  end

  def similar_conflicts
    SyncConflict
      .unresolved
      .where.not(id: id)
      .where(
        existing_expense_id: existing_expense_id,
        conflict_type: conflict_type
      )
  end

  def can_bulk_resolve?
    bulk_resolvable && status_pending?
  end

  def field_differences
    return {} unless differences.present?
    differences
  end

  def formatted_similarity_score
    return "N/A" unless similarity_score
    "#{similarity_score.round(1)}%"
  end

  private

  def should_calculate_similarity?
    new_expense.present? && existing_expense.present? && (conflict_type_duplicate? || conflict_type_similar?)
  end

  def calculate_similarity_score
    return unless new_expense && existing_expense

    score = 0.0
    weight_total = 0.0

    # Amount comparison (40% weight)
    if existing_expense.amount == new_expense.amount
      score += 40
    elsif (existing_expense.amount - new_expense.amount).abs < 1
      score += 30
    elsif (existing_expense.amount - new_expense.amount).abs < 10
      score += 20
    end
    weight_total += 40

    # Date comparison (30% weight)
    if existing_expense.transaction_date == new_expense.transaction_date
      score += 30
    elsif (existing_expense.transaction_date - new_expense.transaction_date).abs <= 1
      score += 20
    elsif (existing_expense.transaction_date - new_expense.transaction_date).abs <= 3
      score += 10
    end
    weight_total += 30

    # Merchant comparison (20% weight)
    if existing_expense.merchant_name == new_expense.merchant_name
      score += 20
    elsif existing_expense.merchant_name&.downcase&.include?(new_expense.merchant_name&.downcase.to_s) ||
          new_expense.merchant_name&.downcase&.include?(existing_expense.merchant_name&.downcase.to_s)
      score += 10
    end
    weight_total += 20

    # Description comparison (10% weight)
    if existing_expense.description == new_expense.description
      score += 10
    elsif existing_expense.description&.downcase&.include?(new_expense.description&.downcase.to_s) ||
          new_expense.description&.downcase&.include?(existing_expense.description&.downcase.to_s)
      score += 5
    end
    weight_total += 10

    self.similarity_score = (score / weight_total * 100).round(2)
  end

  def set_priority
    self.priority ||= case conflict_type
    when "duplicate"
      similarity_score.to_i >= 90 ? 1 : 2
    when "similar"
      3
    when "updated"
      4
    when "needs_review"
      5
    else
      0
    end
  end

  def capture_current_state
    {
      existing_expense: existing_expense.attributes,
      new_expense: new_expense&.attributes,
      conflict: attributes.except("created_at", "updated_at")
    }
  end

  def calculate_changes(before_state)
    after_state = capture_current_state
    changes = {}

    # Compare existing expense
    if before_state["existing_expense"] != after_state["existing_expense"]
      changes["existing_expense"] = {
        before: before_state["existing_expense"],
        after: after_state["existing_expense"]
      }
    end

    # Compare new expense
    if before_state["new_expense"] != after_state["new_expense"]
      changes["new_expense"] = {
        before: before_state["new_expense"],
        after: after_state["new_expense"]
      }
    end

    changes
  end

  def apply_resolution(action, resolution_data)
    case action
    when "keep_existing"
      new_expense&.update!(status: :duplicate)
    when "keep_new"
      existing_expense.update!(status: :duplicate)
      new_expense&.update!(status: :processed)
    when "keep_both"
      new_expense&.update!(status: :processed)
    when "merged"
      merge_expenses(resolution_data)
    when "custom"
      apply_custom_resolution(resolution_data)
    end
  end

  def merge_expenses(merge_data)
    # Merge data from new expense into existing
    updates = {}

    merge_data.each do |field, source|
      if source == "new" && new_expense.respond_to?(field)
        updates[field] = new_expense.send(field)
      end
    end

    existing_expense.update!(updates) if updates.any?
    new_expense&.update!(status: :duplicate)
  end

  def apply_custom_resolution(custom_data)
    # Apply custom field values
    if custom_data["existing_expense"].present?
      existing_expense.update!(custom_data["existing_expense"])
    end

    if custom_data["new_expense"].present? && new_expense
      new_expense.update!(custom_data["new_expense"])
    end
  end

  def restore_state(state)
    if state["existing_expense"].present?
      existing_expense.reload.update!(state["existing_expense"].except("id", "created_at", "updated_at", "lock_version"))
    end

    if state["new_expense"].present? && new_expense
      new_expense.reload.update!(state["new_expense"].except("id", "created_at", "updated_at", "lock_version"))
    end
  end

  def broadcast_resolution
    # Broadcast resolution to connected clients via ActionCable
    SyncStatusChannel.broadcast_to(
      sync_session,
      {
        event: "conflict_resolved",
        conflict_id: id,
        status: status,
        resolution_action: resolution_action
      }
    )
  end
end
