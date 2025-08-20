# frozen_string_literal: true

# Soft Delete Module
# Provides soft delete functionality with undo capability for models
module SoftDelete
  extend ActiveSupport::Concern

  included do
    # Default scope excludes soft deleted records
    default_scope { where(deleted_at: nil) }

    # Scopes for accessing deleted records
    scope :deleted, -> { unscoped.where.not(deleted_at: nil) }
    scope :with_deleted, -> { unscoped }
    scope :recently_deleted, -> { deleted.where(deleted_at: 30.minutes.ago..Time.current) }

    # Callbacks
    before_destroy :check_if_soft_deletable
  end

  # Instance methods
  def soft_delete!(deleted_by: nil)
    transaction do
      self.deleted_at = Time.current
      self.deleted_by = deleted_by if respond_to?(:deleted_by=)
      save!(validate: false)

      # Store in undo history
      create_undo_record if respond_to?(:create_undo_record)
    end
  end

  def soft_delete(deleted_by: nil)
    soft_delete!(deleted_by: deleted_by)
  rescue ActiveRecord::RecordInvalid
    false
  end

  def restore!
    transaction do
      self.deleted_at = nil
      self.deleted_by = nil if respond_to?(:deleted_by=)
      save!(validate: false)

      # Clear from undo history
      clear_undo_record if respond_to?(:clear_undo_record)
    end
  end

  def restore
    restore!
  rescue ActiveRecord::RecordInvalid
    false
  end

  def deleted?
    deleted_at.present?
  end

  def permanent_delete!
    self.class.unscoped.where(id: id).delete_all
  end

  private

  def check_if_soft_deletable
    if self.class.soft_deletable?
      soft_delete!
      throw(:abort)
    end
  end

  class_methods do
    def soft_deletable?
      column_names.include?("deleted_at")
    end

    def soft_delete_all!(deleted_by: nil)
      transaction do
        records = all.to_a

        # Update all records
        update_all(
          deleted_at: Time.current,
          deleted_by: deleted_by
        )

        # Create bulk undo record
        create_bulk_undo_record(records) if respond_to?(:create_bulk_undo_record)

        records
      end
    end

    def restore_all!
      transaction do
        records = deleted.to_a

        # Restore all records
        deleted.update_all(
          deleted_at: nil,
          deleted_by: nil
        )

        # Clear bulk undo record
        clear_bulk_undo_record(records) if respond_to?(:clear_bulk_undo_record)

        records
      end
    end
  end
end
