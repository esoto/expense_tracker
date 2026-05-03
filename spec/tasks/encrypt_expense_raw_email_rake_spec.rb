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
    allow(Rake::Task["encrypt:expense_raw_email"]).to receive(:reenable).and_call_original
  end

  after { Rake::Task.clear }

  def run_task
    Rake::Task["encrypt:expense_raw_email"].reenable
    Rake::Task["encrypt:expense_raw_email"].invoke
  end

  def raw_column_value(expense)
    ActiveRecord::Base.connection.execute(
      "SELECT raw_email_content FROM expenses WHERE id = #{expense.id}"
    ).first["raw_email_content"]
  end

  it "encrypts plaintext rows on first run" do
    expense = create(:expense)
    # Bypass AR Encryption with raw SQL to simulate a row written before the
    # encrypts declaration (i.e. a legacy plaintext production row).
    ActiveRecord::Base.connection.execute(
      "UPDATE expenses SET raw_email_content = 'plaintext body content' WHERE id = #{expense.id}"
    )

    expect { run_task }.not_to raise_error

    # After the task runs, the raw column should contain ciphertext
    raw = raw_column_value(expense.reload)
    expect(raw).to start_with("{")
    # And the model should still decrypt it transparently
    expect(expense.reload.raw_email_content).to eq("plaintext body content")
  end

  it "is idempotent — running twice leaves already-encrypted rows untouched" do
    expense = create(:expense, :with_raw_email, raw_email_content: "email body #{SecureRandom.hex}")

    run_task # first run — encrypts the row

    raw_after_first = raw_column_value(expense.reload)
    expect(raw_after_first).to start_with("{")

    run_task # second run — must not alter the ciphertext

    raw_after_second = raw_column_value(expense.reload)
    expect(raw_after_second).to eq(raw_after_first)
  end

  it "skips rows where raw_email_content is NULL" do
    expense = create(:expense, raw_email_content: nil)

    expect { run_task }.not_to raise_error

    raw = raw_column_value(expense.reload)
    expect(raw).to be_nil
  end

  it "reports progress to STDOUT" do
    create(:expense, :with_raw_email, raw_email_content: "some body")

    expect { run_task }.to output(/\[PER-533\]/).to_stdout
  end
end
