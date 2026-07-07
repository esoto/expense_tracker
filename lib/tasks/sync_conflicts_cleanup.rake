# frozen_string_literal: true

# fix/silent-duplicate-skip: One-off cleanup for the SyncConflict ghost rows
# that predate the silent-duplicate-skip policy change.
#
# Before this fix, ConflictDetectionService created a SyncConflict row for
# every "duplicate" detection (>=90% similarity) and soft-deleted the
# incoming new_expense. Nothing ever un-persists the SyncConflict row itself,
# so once the soft-deleted new_expense is later hard-deleted (or simply
# excluded by Expense's default_scope, which hides deleted_at rows), the
# conflict becomes an unresolvable ghost: "the same expense seen again", with
# nothing left to actually resolve. Production accumulated 75 such rows, all
# status=pending.
#
# Usage:
#   bin/rails sync_conflicts:cleanup_orphaned
#
# Idempotent — re-running finds zero matching rows once cleaned up, and only
# ever touches status=pending rows whose new_expense is gone or soft-deleted.
# Resolved/ignored/auto_resolved conflicts and conflicts with a live
# new_expense are never touched.
namespace :sync_conflicts do
  desc "Delete orphaned pending SyncConflict rows whose new_expense is missing or soft-deleted"
  task cleanup_orphaned: :environment do
    orphaned_scope = SyncConflict
      .where(status: "pending")
      .where(
        "new_expense_id IS NULL OR NOT EXISTS (" \
        "SELECT 1 FROM expenses e WHERE e.id = sync_conflicts.new_expense_id AND e.deleted_at IS NULL" \
        ")"
      )

    found = orphaned_scope.count
    # destroy_all (not delete_all) so dependent conflict_resolutions rows are
    # cleaned up too, even though pending conflicts rarely have any.
    deleted = orphaned_scope.destroy_all.size

    message = "[SyncConflict cleanup] pending+orphaned rows found=#{found} deleted=#{deleted}"
    Rails.logger.info message
    puts message
  end
end
