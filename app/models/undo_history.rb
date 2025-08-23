# frozen_string_literal: true

# UndoHistory Model
# Tracks soft deletions and enables undo functionality
class UndoHistory < ApplicationRecord
  # Constants
  UNDO_WINDOW = 30.minutes
  MAX_UNDO_RECORDS = 100

  # Associations
  belongs_to :undoable, polymorphic: true, optional: true
  belongs_to :user, optional: true # Track who performed the action

  # Validations
  validates :action_type, presence: true
  validates :record_data, presence: true
  validates :undoable_type, presence: true

  # Scopes
  scope :recent, -> { where(created_at: UNDO_WINDOW.ago..Time.current) }
  scope :pending, -> { where(undone_at: nil, expired_at: nil) }
  scope :undone, -> { where.not(undone_at: nil) }
  scope :expired, -> { where.not(expired_at: nil) }
  scope :for_user, ->(user) { where(user: user) }
  scope :bulk_operations, -> { where(is_bulk: true) }

  # Callbacks
  before_create :set_expiration
  after_create :cleanup_old_records

  # Enums
  enum action_type: {
    soft_delete: 0,
    bulk_delete: 1,
    bulk_update: 2,
    bulk_categorize: 3
  }

  # Class methods
  def self.create_for_deletion(record, user: nil)
    create!(
      undoable: record,
      undoable_type: record.class.name,
      undoable_id: record.id,
      action_type: :soft_delete,
      record_data: record.attributes,
      user: user,
      description: "Deleted #{record.class.name.humanize.downcase}: #{record.try(:name) || record.try(:merchant_name) || record.id}"
    )
  end

  def self.create_for_bulk_deletion(records, user: nil)
    create!(
      undoable_type: records.first.class.name,
      action_type: :bulk_delete,
      record_data: {
        ids: records.map(&:id),
        records: records.map(&:attributes)
      },
      user: user,
      is_bulk: true,
      description: "Deleted #{records.count} #{records.first.class.name.humanize.downcase.pluralize}",
      affected_count: records.count
    )
  end

  def self.create_for_bulk_update(records, changes, user: nil)
    create!(
      undoable_type: records.first.class.name,
      action_type: :bulk_update,
      record_data: {
        ids: records.map(&:id),
        original_values: records.map { |r| r.attributes.slice(*changes.keys) },
        changes: changes
      },
      user: user,
      is_bulk: true,
      description: "Updated #{records.count} #{records.first.class.name.humanize.downcase.pluralize}",
      affected_count: records.count
    )
  end

  # Instance methods
  def undo!
    return false if undone? || expired?

    transaction do
      case action_type
      when "soft_delete"
        undo_single_deletion
      when "bulk_delete"
        undo_bulk_deletion
      when "bulk_update"
        undo_bulk_update
      when "bulk_categorize"
        undo_bulk_categorization
      end

      update!(undone_at: Time.current)
      true
    end
  rescue => e
    Rails.logger.error "Undo failed: #{e.message}"
    false
  end

  def undoable?
    !undone? && !expired? && within_undo_window?
  end

  def undone?
    undone_at.present?
  end

  def expired?
    expired_at.present? || (expires_at && expires_at < Time.current)
  end

  def within_undo_window?
    created_at > UNDO_WINDOW.ago
  end

  def time_remaining
    return 0 if expired? || undone?

    seconds_left = (expires_at - Time.current).to_i
    seconds_left > 0 ? seconds_left : 0
  end

  private

  def set_expiration
    self.expires_at ||= UNDO_WINDOW.from_now
  end

  def cleanup_old_records
    # Keep only the most recent MAX_UNDO_RECORDS
    if self.class.count > MAX_UNDO_RECORDS
      self.class
        .order(created_at: :desc)
        .offset(MAX_UNDO_RECORDS)
        .destroy_all
    end
  end

  def undo_single_deletion
    return false unless undoable_type.present? && record_data.present?

    klass = undoable_type.constantize
    record = klass.with_deleted.find_by(id: record_data["id"])

    if record
      record.restore!
    else
      # Recreate the record if it was permanently deleted
      klass.create!(record_data.except("id", "created_at", "updated_at", "deleted_at"))
    end
  end

  def undo_bulk_deletion
    return false unless record_data["ids"].present?

    klass = undoable_type.constantize
    records = klass.with_deleted.where(id: record_data["ids"])

    records.each(&:restore!)

    # Recreate any missing records
    missing_ids = record_data["ids"] - records.pluck(:id)
    if missing_ids.any? && record_data["records"].present?
      record_data["records"].each do |attrs|
        next unless missing_ids.include?(attrs["id"])
        klass.create!(attrs.except("id", "created_at", "updated_at", "deleted_at"))
      end
    end
  end

  def undo_bulk_update
    return false unless record_data["ids"].present? && record_data["original_values"].present?

    klass = undoable_type.constantize
    records = klass.where(id: record_data["ids"])

    records.each_with_index do |record, index|
      original_values = record_data["original_values"][index]
      record.update!(original_values) if original_values.present?
    end
  end

  def undo_bulk_categorization
    undo_bulk_update # Same logic for categorization
  end
end
