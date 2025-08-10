# frozen_string_literal: true

require "rails_helper"

RSpec.describe QueueMonitor do
  # Clean up before each test across all describe blocks
  before do
    Rails.cache.clear
    clean_solid_queue_tables
  end

  describe ".queue_status" do
    it "returns comprehensive queue status" do
      queue_status = described_class.queue_status

      expect(queue_status).to include(
        :pending,
        :processing,
        :completed,
        :failed,
        :paused_queues,
        :active_jobs,
        :failed_jobs,
        :queue_depth_by_name,
        :processing_rate,
        :estimated_completion_time,
        :worker_status,
        :health_status
      )
    end

    it "caches the result for the specified duration" do
      # Create some test data first
      job = create_job_with_ready_execution

      first_call = described_class.queue_status

      # Change the data but cached result should remain the same
      job2 = create_job_with_ready_execution

      second_call = described_class.queue_status

      expect(first_call).to eq(second_call)
      expect(first_call[:pending]).to eq(1) # Should be cached at 1, not 2
    end

    context "with various job states" do
      it "counts pending jobs correctly" do
        # Create a job with ready execution
        job1 = create_job_with_ready_execution

        # Create a scheduled job that's due (in the past)
        job2 = create_job_with_scheduled_execution(scheduled_at: 1.minute.ago)

        expect(described_class.pending_jobs_count).to eq(2)
      end

      it "counts processing jobs correctly" do
        # Create jobs with claimed executions (processing)
        job1 = create_job_with_claimed_execution
        job2 = create_job_with_claimed_execution

        expect(described_class.processing_jobs_count).to eq(2)
      end

      it "counts completed jobs correctly" do
        create_completed_job(finished_at: 1.hour.ago)
        create_completed_job(finished_at: 2.days.ago) # Outside 24h window

        expect(described_class.completed_jobs_count).to eq(1)
      end

      it "counts failed jobs correctly" do
        job = create_job_with_failed_execution

        expect(described_class.failed_jobs_count).to eq(1)
      end
    end
  end

  describe ".pending_jobs" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "returns pending jobs with proper formatting" do
      job = create_job_with_ready_execution
      pending_jobs = described_class.pending_jobs

      expect(pending_jobs.first).to include(
        id: job.id,
        class_name: job.class_name,
        queue_name: job.queue_name,
        status: "ready"
      )
    end

    it "limits results to MAX_ACTIVE_JOBS_DISPLAY" do
      15.times do
        create_job_with_ready_execution
      end

      expect(described_class.pending_jobs.size).to eq(10)
    end

    it "orders by priority and creation time" do
      low_priority_job = create_job_with_ready_execution(priority: 1)
      high_priority_job = create_job_with_ready_execution(priority: 10)

      pending_jobs = described_class.pending_jobs
      expect(pending_jobs.first[:priority]).to eq(10)
    end
  end

  describe ".processing_jobs" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "returns currently processing jobs with process info" do
      job = create_job_with_claimed_execution
      processing_jobs = described_class.processing_jobs

      expect(processing_jobs.first).to include(
        id: job.id,
        status: "processing"
      )

      expect(processing_jobs.first[:process_info]).to be_present
    end
  end

  describe ".failed_jobs" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "returns failed jobs with error details" do
      job = create_job_with_failed_execution(error: "Test error message")
      failed_jobs = described_class.failed_jobs

      expect(failed_jobs.first).to include(
        id: job.id,
        status: "failed",
        error: "Test error message"
      )
    end
  end

  describe ".queue_depth_by_name" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "groups jobs by queue name" do
      job1 = create_job_with_ready_execution(queue_name: "default")
      job2 = create_job_with_ready_execution(queue_name: "default")
      job3 = create_job_with_ready_execution(queue_name: "urgent")

      depths = described_class.queue_depth_by_name

      expect(depths["default"]).to eq(2)
      expect(depths["urgent"]).to eq(1)
    end
  end

  describe ".processing_rate" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "calculates average jobs per minute" do
      5.times do
        create_completed_job(finished_at: 30.minutes.ago)
      end

      rate = described_class.processing_rate
      expect(rate).to be_within(0.1).of(5.0 / 60)
    end

    it "returns 0 when no jobs completed recently" do
      expect(described_class.processing_rate).to eq(0)
    end
  end

  describe ".estimate_completion_time" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    context "with pending jobs and positive processing rate" do
      before do
        10.times { create_job_with_ready_execution }
        5.times { create_completed_job(finished_at: 30.minutes.ago) }
      end

      it "estimates completion time based on rate" do
        completion_time = described_class.estimate_completion_time
        expect(completion_time).to be_a(Time)
        expect(completion_time).to be > Time.current
      end
    end

    context "with no pending jobs" do
      it "returns nil" do
        expect(described_class.estimate_completion_time).to be_nil
      end
    end

    context "with zero processing rate" do
      before do
        create_job_with_ready_execution
      end

      it "returns nil" do
        expect(described_class.estimate_completion_time).to be_nil
      end
    end
  end

  describe ".worker_status" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "returns worker information" do
      # Create healthy worker (heartbeat < 1 minute ago)
      healthy_worker = create_worker_process(last_heartbeat_at: 30.seconds.ago)

      # Create stale worker (heartbeat > 1 minute but < 5 minutes ago)
      stale_worker = create_worker_process(last_heartbeat_at: 2.minutes.ago)

      status = described_class.worker_status

      expect(status[:total]).to eq(2)
      expect(status[:healthy]).to eq(1)
      expect(status[:stale]).to eq(1)
      expect(status[:processes]).to be_an(Array)
      expect(status[:processes].size).to eq(2)
    end
  end

  describe ".calculate_health_status" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    context "with no healthy workers" do
      it "returns critical status" do
        health = described_class.calculate_health_status
        expect(health[:status]).to eq("critical")
        expect(health[:message]).to include("No healthy workers")
      end
    end

    context "with high failed job count" do
      before do
        create_worker_process
        101.times { create_job_with_failed_execution }
      end

      it "returns critical status" do
        health = described_class.calculate_health_status
        expect(health[:status]).to eq("critical")
        expect(health[:message]).to include("High number of failed jobs")
      end
    end

    context "with large queue backlog" do
      it "returns warning status" do
        create_worker_process

        # Create jobs in batches to avoid timeouts
        1001.times { create_job_with_ready_execution }

        health = described_class.calculate_health_status
        expect(health[:status]).to eq("warning")
        expect(health[:message]).to include("Large queue backlog")
      end
    end

    context "with normal operations" do
      before { create_worker_process }

      it "returns healthy status" do
        health = described_class.calculate_health_status
        expect(health[:status]).to eq("healthy")
        expect(health[:message]).to include("operating normally")
      end
    end
  end

  describe ".pause_queue" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "pauses a specific queue" do
      result = described_class.pause_queue("default")

      expect(result).to be true
      expect(SolidQueue::Pause.exists?(queue_name: "default")).to be true
    end

    it "pauses all queues when no name specified" do
      job1 = create_job_with_ready_execution(queue_name: "default")
      job2 = create_job_with_ready_execution(queue_name: "urgent")

      result = described_class.pause_queue(nil)

      expect(result).to be true
      expect(SolidQueue::Pause.pluck(:queue_name)).to include("default", "urgent")
    end

    it "clears the cache after pausing" do
      expect(Rails.cache).to receive(:delete).with("queue_monitor:status")
      described_class.pause_queue("default")
    end
  end

  describe ".resume_queue" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
      SolidQueue::Pause.create!(queue_name: "default")
      SolidQueue::Pause.create!(queue_name: "urgent")
    end

    it "resumes a specific queue" do
      result = described_class.resume_queue("default")

      expect(result).to be true
      expect(SolidQueue::Pause.exists?(queue_name: "default")).to be false
      expect(SolidQueue::Pause.exists?(queue_name: "urgent")).to be true
    end

    it "resumes all queues when no name specified" do
      result = described_class.resume_queue(nil)

      expect(result).to be true
      expect(SolidQueue::Pause.count).to eq(0)
    end
  end

  describe ".retry_failed_job" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "moves job from failed to ready" do
      job = create_job_with_failed_execution
      job_id = job.id

      result = described_class.retry_failed_job(job_id)

      expect(result).to be true
      expect(SolidQueue::FailedExecution.exists?(job_id: job_id)).to be false
      expect(SolidQueue::ReadyExecution.exists?(job_id: job_id)).to be true
    end

    it "returns false for non-existent job" do
      result = described_class.retry_failed_job(999999)
      expect(result).to be false
    end
  end

  describe ".retry_all_failed_jobs" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "retries all failed jobs and returns count" do
      3.times { create_job_with_failed_execution }

      count = described_class.retry_all_failed_jobs

      expect(count).to eq(3)
      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::ReadyExecution.count).to eq(3)
    end
  end

  describe ".clear_failed_job" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "removes job from failed executions and marks as finished" do
      job = create_job_with_failed_execution

      result = described_class.clear_failed_job(job.id)

      expect(result).to be true
      expect(SolidQueue::FailedExecution.exists?(job_id: job.id)).to be false
      expect(job.reload.finished_at).to be_present
    end
  end

  describe ".detailed_metrics" do
    before do
      Rails.cache.clear
      clean_solid_queue_tables
    end

    it "returns comprehensive metrics" do
      create_worker_process

      job1 = create_job_with_ready_execution
      job2 = create_job_with_claimed_execution
      job3 = create_job_with_failed_execution

      metrics = described_class.detailed_metrics

      expect(metrics).to include(
        :queue_status,
        :performance,
        :queue_distribution,
        :worker_utilization,
        :error_rate
      )

      expect(metrics[:performance]).to include(
        :processing_rate,
        :average_wait_time,
        :average_processing_time,
        :throughput_per_hour
      )
    end
  end

  # Helper methods for creating test data

  def clean_solid_queue_tables
    # Clean in reverse dependency order to avoid foreign key violations
    SolidQueue::ReadyExecution.delete_all
    SolidQueue::ScheduledExecution.delete_all
    SolidQueue::ClaimedExecution.delete_all
    SolidQueue::FailedExecution.delete_all
    SolidQueue::BlockedExecution.delete_all
    SolidQueue::RecurringExecution.delete_all if defined?(SolidQueue::RecurringExecution)
    SolidQueue::Job.delete_all
    SolidQueue::Process.delete_all
    SolidQueue::Pause.delete_all
    SolidQueue::Semaphore.delete_all if defined?(SolidQueue::Semaphore)
    SolidQueue::RecurringTask.delete_all if defined?(SolidQueue::RecurringTask)
  end

  # Create a job with a ready execution (SolidQueue does this automatically)
  def create_job_with_ready_execution(attributes = {})
    # SolidQueue automatically creates ready execution for non-scheduled, non-finished jobs
    SolidQueue::Job.create!(
      queue_name: attributes[:queue_name] || "default",
      class_name: attributes[:class_name] || "TestJob",
      arguments: attributes[:arguments] || { id: SecureRandom.hex(8) }.to_json,
      priority: attributes[:priority] || 0,
      active_job_id: attributes[:active_job_id] || SecureRandom.uuid
    )
  end

  # Create a job with a scheduled execution
  def create_job_with_scheduled_execution(attributes = {})
    # SolidQueue automatically creates scheduled execution when scheduled_at is set
    SolidQueue::Job.create!(
      queue_name: attributes[:queue_name] || "default",
      class_name: attributes[:class_name] || "TestJob",
      arguments: attributes[:arguments] || { id: SecureRandom.hex(8) }.to_json,
      priority: attributes[:priority] || 0,
      active_job_id: attributes[:active_job_id] || SecureRandom.uuid,
      scheduled_at: attributes[:scheduled_at] || 1.hour.from_now
    )
  end

  # Create a job with claimed execution (processing)
  def create_job_with_claimed_execution(attributes = {})
    job = create_bare_job(attributes)
    process = attributes[:process] || create_worker_process
    SolidQueue::ClaimedExecution.create!(
      job: job,
      process: process
    )
    job
  end

  # Create a job with failed execution
  def create_job_with_failed_execution(attributes = {})
    job = create_bare_job(attributes)
    SolidQueue::FailedExecution.create!(
      job: job,
      error: attributes[:error] || "Test error"
    )
    job
  end

  # Create a completed job (finished)
  def create_completed_job(attributes = {})
    create_bare_job(attributes.merge(
      finished_at: attributes[:finished_at] || 1.hour.ago
    ))
  end

  # Create a bare job without any execution (for manual control)
  def create_bare_job(attributes = {})
    job = SolidQueue::Job.create!(
      queue_name: attributes[:queue_name] || "default",
      class_name: attributes[:class_name] || "TestJob",
      arguments: attributes[:arguments] || { id: SecureRandom.hex(8) }.to_json,
      priority: attributes[:priority] || 0,
      active_job_id: attributes[:active_job_id] || SecureRandom.uuid,
      scheduled_at: attributes[:scheduled_at],
      finished_at: attributes[:finished_at]
    )

    # Remove any auto-created executions for complete control
    SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all
    SolidQueue::ScheduledExecution.where(job_id: job.id).destroy_all

    job
  end

  # Backwards compatibility aliases
  def create_job(attributes = {})
    create_bare_job(attributes)
  end

  def create_ready_execution_for(job)
    # Check if job already has any execution
    return job if SolidQueue::ReadyExecution.exists?(job_id: job.id)

    SolidQueue::ReadyExecution.create!(
      job: job,
      queue_name: job.queue_name,
      priority: job.priority
    )
    job
  end

  def create_scheduled_execution_for(job, scheduled_at: 1.hour.from_now)
    # Remove any existing executions first
    SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all

    SolidQueue::ScheduledExecution.create!(
      job: job,
      queue_name: job.queue_name,
      priority: job.priority,
      scheduled_at: scheduled_at
    )
    job
  end

  def create_claimed_execution_for(job, process: nil)
    # Remove any existing executions first
    SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all
    SolidQueue::ScheduledExecution.where(job_id: job.id).destroy_all

    process ||= create_worker_process
    SolidQueue::ClaimedExecution.create!(
      job: job,
      process: process
    )
    job
  end

  def create_failed_execution_for(job, error: "Test error")
    # Remove any existing executions first
    SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all
    SolidQueue::ScheduledExecution.where(job_id: job.id).destroy_all
    SolidQueue::ClaimedExecution.where(job_id: job.id).destroy_all

    SolidQueue::FailedExecution.create!(
      job: job,
      error: error
    )
    job
  end

  def create_worker_process(attributes = {})
    SolidQueue::Process.create!(
      kind: attributes[:kind] || "Worker",
      last_heartbeat_at: attributes[:last_heartbeat_at] || Time.current,
      pid: attributes[:pid] || Process.pid + rand(10000),
      hostname: attributes[:hostname] || "test-host-#{SecureRandom.hex(4)}",
      name: attributes[:name] || "worker-#{SecureRandom.hex(8)}",
      metadata: attributes[:metadata]
    )
  end
end
