# frozen_string_literal: true

require "rails_helper"

# Solid Queue dispatch-level contract for MetricsCalculationJob#limits_concurrency.
#
# The unit spec (metrics_calculation_job_spec.rb) asserts *configuration* —
# concurrency_limit, concurrency_key, and concurrency_duration are set correctly
# at the class level. That catches constant/DSL regressions but NOT runtime
# enforcement. This spec closes that gap: it exercises
# SolidQueue::Job.enqueue end-to-end and asserts the semaphore actually
# partitions the second job into solid_queue_blocked_executions.
#
# Coverage rationale:
#   - Catches Solid Queue version regressions (dispatch path changes)
#   - Catches accidental removal of the `limits_concurrency` DSL call
#   - Catches a worker/adapter misconfiguration that bypasses the semaphore
#
# We enqueue via SolidQueue::Job.enqueue directly (rather than perform_later)
# to bypass Active Job's :test adapter and land rows in the real tables.
#
# See PER-542.
RSpec.describe MetricsCalculationJob, "Solid Queue dispatch concurrency", type: :job, integration: true do
  let!(:account) { create(:email_account) }

  before do
    # Clean slate — other specs using Active Job's :test adapter don't touch
    # these tables, but prior integration specs might leave rows behind.
    SolidQueue::Job.delete_all
    SolidQueue::Semaphore.delete_all
  end

  # Build and enqueue an ActiveJob instance. Uses SolidQueue::Job.enqueue
  # directly so we exercise the real dispatch → acquire_concurrency_lock → ready/blocked
  # path regardless of Rails' configured queue adapter.
  def enqueue(email_account_id:)
    SolidQueue::Job.enqueue(
      described_class.new(email_account_id: email_account_id)
    )
  end

  describe "two jobs with the same email_account_id" do
    before do
      enqueue(email_account_id: account.id)
      enqueue(email_account_id: account.id)
    end

    let(:jobs) { SolidQueue::Job.where(class_name: described_class.name) }
    let(:ready) { SolidQueue::ReadyExecution.where(job_id: jobs.pluck(:id)) }
    let(:blocked) { SolidQueue::BlockedExecution.where(job_id: jobs.pluck(:id)) }

    it "persists both jobs to solid_queue_jobs" do
      expect(jobs.count).to eq(2)
    end

    it "puts exactly one job in ready" do
      expect(ready.count).to eq(1)
    end

    it "puts exactly one job in blocked" do
      expect(blocked.count).to eq(1)
    end

    it "keys the blocked execution by MetricsCalculationJob/<account_id>" do
      expect(blocked.first.concurrency_key).to eq("#{described_class.name}/#{account.id}")
    end

    it "records a semaphore for the held lock" do
      expect(
        SolidQueue::Semaphore.where(key: "#{described_class.name}/#{account.id}")
      ).to exist
    end
  end

  describe "two jobs with different email_account_ids" do
    let!(:other_account) do
      create(:email_account, email: "other_#{SecureRandom.hex(4)}@example.com")
    end

    before do
      enqueue(email_account_id: account.id)
      enqueue(email_account_id: other_account.id)
    end

    let(:jobs) { SolidQueue::Job.where(class_name: described_class.name) }

    it "puts both jobs in ready (semaphore partitions by account)" do
      ready = SolidQueue::ReadyExecution.where(job_id: jobs.pluck(:id))
      expect(ready.count).to eq(2)
    end

    it "blocks no jobs" do
      blocked = SolidQueue::BlockedExecution.where(job_id: jobs.pluck(:id))
      expect(blocked).to be_empty
    end

    it "creates a distinct semaphore per account" do
      keys = SolidQueue::Semaphore.pluck(:key)
      expect(keys).to contain_exactly(
        "#{described_class.name}/#{account.id}",
        "#{described_class.name}/#{other_account.id}"
      )
    end
  end

  describe "three jobs with the same email_account_id" do
    # Guards against a broken BlockedExecution.create_or_find_by! that could
    # let a later job silently overwrite an earlier blocked row.
    before { 3.times { enqueue(email_account_id: account.id) } }

    let(:jobs) { SolidQueue::Job.where(class_name: described_class.name) }

    it "puts exactly one job in ready" do
      expect(SolidQueue::ReadyExecution.where(job_id: jobs.pluck(:id)).count).to eq(1)
    end

    it "puts the other two jobs in blocked" do
      expect(SolidQueue::BlockedExecution.where(job_id: jobs.pluck(:id)).count).to eq(2)
    end
  end

  describe "fan-out mode (nil email_account_id)" do
    before do
      SolidQueue::Job.enqueue(described_class.new(email_account_id: nil))
      SolidQueue::Job.enqueue(described_class.new(email_account_id: nil))
    end

    it "uses the 'all_accounts' fallback concurrency key" do
      blocked = SolidQueue::BlockedExecution.where(
        concurrency_key: "#{described_class.name}/all_accounts"
      )
      expect(blocked.count).to eq(1)
    end
  end
end
