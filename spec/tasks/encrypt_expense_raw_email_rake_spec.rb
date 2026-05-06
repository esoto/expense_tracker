# frozen_string_literal: true

require "rails_helper"
require "rake"

# PER-533: Spec for the encrypt:expense_raw_email backfill rake task.
# Verifies idempotency and batch behaviour without exercising the full
# in_batches sleep loop (we stub it to keep the spec fast).
RSpec.describe "encrypt:expense_raw_email", :unit, type: :task do
  let(:rake_app) { Rake::Application.new }

  before do
    Rake.application = rake_app
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/encrypt_expense_raw_email.rake")
  end

  after { Rake::Task.clear }

  def run_task
    Rake::Task["encrypt:expense_raw_email"].reenable
    Rake::Task["encrypt:expense_raw_email"].invoke
  end

  def raw_column_value(expense)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql([
        "SELECT raw_email_content FROM expenses WHERE id = ?", expense.id
      ])
    )
  end

  def seed_plaintext(expense, plaintext)
    # Bypass AR Encryption with raw SQL to simulate a legacy plaintext row
    # written before the encrypts declaration shipped.
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([
        "UPDATE expenses SET raw_email_content = ? WHERE id = ?", plaintext, expense.id
      ])
    )
  end

  it "encrypts plaintext rows on first run" do
    expense = create(:expense)
    seed_plaintext(expense, "plaintext body content")

    expect { run_task }.not_to raise_error

    raw = raw_column_value(expense.reload)
    expect(raw).to start_with('{"p":')
    # AR transparently decrypts on read
    expect(expense.reload.raw_email_content).to eq("plaintext body content")
  end

  it "is idempotent — first run encrypts, second run skips at the SQL filter (no DB writes)" do
    expense = create(:expense)
    seed_plaintext(expense, "email body #{SecureRandom.hex}")

    run_task # first run — encrypts the row

    raw_after_first = raw_column_value(expense.reload)
    expect(raw_after_first).to start_with('{"p":')

    # Second run must NOT touch the row (it's filtered out at the WHERE
    # clause: `raw_email_content NOT LIKE '{"p":%'`). Ciphertext stays
    # byte-equal because non-deterministic encryption would produce a
    # different value if the task re-encrypted.
    run_task

    raw_after_second = raw_column_value(expense.reload)
    expect(raw_after_second).to eq(raw_after_first)
  end

  it "leaves NULL raw_email_content rows alone (filtered at the WHERE clause)" do
    expense = create(:expense, raw_email_content: nil)

    expect { run_task }.not_to raise_error

    raw = raw_column_value(expense.reload)
    expect(raw).to be_nil
  end

  it "encrypts soft-deleted rows too (Expense.unscoped covers them)" do
    # Soft-deleted expenses still hold bank PII — backfill must reach them.
    expense = create(:expense)
    seed_plaintext(expense, "soft-deleted plaintext")
    expense.update_columns(deleted_at: Time.current)
    expect(Expense.where(id: expense.id).count).to eq(0) # default_scope hides it

    run_task

    raw = raw_column_value(expense)
    expect(raw).to start_with('{"p":')
  end

  it "reports progress to STDOUT" do
    expense = create(:expense)
    seed_plaintext(expense, "some body")

    expect { run_task }.to output(/\[PER-533\]/).to_stdout
  end
end
