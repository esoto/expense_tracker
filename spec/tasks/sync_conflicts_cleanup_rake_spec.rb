# frozen_string_literal: true

require "rails_helper"
require "rake"

# fix/silent-duplicate-skip: Spec for the sync_conflicts:cleanup_orphaned
# rake task, which removes the pending SyncConflict ghost rows left behind
# by the pre-fix behaviour (a SyncConflict created for every duplicate, with
# no way to un-persist it once the new_expense is gone or soft-deleted).
RSpec.describe "sync_conflicts:cleanup_orphaned", :unit, type: :task do
  let(:rake_app) { Rake::Application.new }

  before do
    Rake.application = rake_app
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/sync_conflicts_cleanup.rake")
  end

  after { Rake::Task.clear }

  def run_task
    Rake::Task["sync_conflicts:cleanup_orphaned"].reenable
    Rake::Task["sync_conflicts:cleanup_orphaned"].invoke
  end

  let(:email_account) { create(:email_account) }

  it "deletes a pending conflict whose new_expense has been soft-deleted" do
    conflict = create(:sync_conflict, :with_new_expense, status: "pending")
    conflict.new_expense.update_columns(deleted_at: Time.current)

    expect { run_task }.to change(SyncConflict, :count).by(-1)
    expect(SyncConflict.where(id: conflict.id)).not_to exist
  end

  it "deletes a pending conflict with no new_expense at all (new_expense_id is NULL)" do
    # A DB-level FK (RESTRICT) prevents hard-deleting an Expense still
    # referenced by a SyncConflict, so in practice "gone" means soft-deleted
    # (covered above). This covers the defensive NULL branch of the query.
    conflict = create(:sync_conflict, status: "pending", new_expense: nil)

    expect { run_task }.to change(SyncConflict, :count).by(-1)
    expect(SyncConflict.where(id: conflict.id)).not_to exist
  end

  it "keeps a pending conflict whose new_expense is still live" do
    conflict = create(:sync_conflict, :with_new_expense, status: "pending")

    expect { run_task }.not_to change(SyncConflict, :count)
    expect(SyncConflict.where(id: conflict.id)).to exist
  end

  it "keeps a resolved conflict even if its new_expense is orphaned" do
    conflict = create(:sync_conflict, :with_new_expense, :resolved)
    conflict.new_expense.update_columns(deleted_at: Time.current)

    expect { run_task }.not_to change(SyncConflict, :count)
    expect(SyncConflict.where(id: conflict.id)).to exist
  end

  it "is idempotent — a second run finds nothing left to delete" do
    conflict = create(:sync_conflict, :with_new_expense, status: "pending")
    conflict.new_expense.update_columns(deleted_at: Time.current)

    run_task
    expect(SyncConflict.where(id: conflict.id)).not_to exist

    expect { run_task }.not_to change(SyncConflict, :count)
  end

  it "reports the found and deleted counts to STDOUT" do
    conflict = create(:sync_conflict, :with_new_expense, status: "pending")
    conflict.new_expense.update_columns(deleted_at: Time.current)

    expect { run_task }.to output(/found=1 deleted=1/).to_stdout
  end
end
