# Background Job Testing Helpers
# Provides utilities for testing jobs with Solid Queue integration

module JobHelpers
  extend ActiveSupport::Concern

  included do
    # Clear all jobs before each test
    before do
      clear_enqueued_jobs
      clear_performed_jobs
    end
  end

  # Job queue management
  def clear_enqueued_jobs
    SolidQueue::Job.destroy_all if defined?(SolidQueue::Job)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
  end

  def clear_performed_jobs
    SolidQueue::Job.where.not(finished_at: nil).destroy_all if defined?(SolidQueue::Job)
    ActiveJob::Base.queue_adapter.performed_jobs.clear if ActiveJob::Base.queue_adapter.respond_to?(:performed_jobs)
  end

  def enqueued_jobs
    if defined?(SolidQueue::Job)
      SolidQueue::Job.where(finished_at: nil).pluck(:class_name, :arguments, :queue_name)
    else
      ActiveJob::Base.queue_adapter.enqueued_jobs
    end
  end

  def performed_jobs
    if defined?(SolidQueue::Job)
      SolidQueue::Job.where.not(finished_at: nil).pluck(:class_name, :arguments, :queue_name, :finished_at)
    else
      ActiveJob::Base.queue_adapter.performed_jobs
    end
  end

  # Job execution helpers
  def perform_enqueued_jobs(queue: nil)
    if defined?(SolidQueue::Job)
      jobs = queue ? SolidQueue::Job.where(queue_name: queue, finished_at: nil) : SolidQueue::Job.where(finished_at: nil)
      jobs.find_each do |job|
        perform_solid_queue_job(job)
      end
    else
      ActiveJob::TestHelper.perform_enqueued_jobs(queue: queue)
    end
  end

  def perform_solid_queue_job(job)
    job_class = job.class_name.constantize
    job_instance = job_class.new(*job.arguments)
    job_instance.job_id = job.job_id

    begin
      job_instance.perform_now
      job.update!(finished_at: Time.current)
    rescue StandardError => e
      job.update!(finished_at: Time.current, error: e.message)
      raise e
    end
  end

  def drain_queue(queue_name = 'default')
    perform_enqueued_jobs(queue: queue_name)
  end

  # Job scheduling helpers
  def assert_job_enqueued(job_class, args: nil, queue: nil, at: nil, &block)
    initial_count = job_count(job_class, args: args, queue: queue)

    result = block.call if block_given?

    final_count = job_count(job_class, args: args, queue: queue)
    expect(final_count).to be > initial_count,
      "Expected #{job_class} to be enqueued, but job count remained #{initial_count}"

    if at
      job = find_job(job_class, args: args, queue: queue)
      expect(job[:at]).to be_within(1.second).of(at)
    end

    result
  end

  def assert_no_job_enqueued(job_class, args: nil, queue: nil, &block)
    initial_count = job_count(job_class, args: args, queue: queue)

    result = block.call if block_given?

    final_count = job_count(job_class, args: args, queue: queue)
    expect(final_count).to eq(initial_count),
      "Expected no #{job_class} jobs to be enqueued, but count increased from #{initial_count} to #{final_count}"

    result
  end

  def assert_job_performed(job_class, args: nil, &block)
    initial_count = performed_job_count(job_class, args: args)

    result = block.call if block_given?

    final_count = performed_job_count(job_class, args: args)
    expect(final_count).to be > initial_count,
      "Expected #{job_class} to be performed, but performed count remained #{initial_count}"

    result
  end

  # Job inspection helpers
  def job_count(job_class, args: nil, queue: nil)
    jobs = enqueued_jobs.select { |job| job[0] == job_class.name }
    jobs = jobs.select { |job| job[2] == queue } if queue
    jobs = jobs.select { |job| job[1] == args } if args
    jobs.count
  end

  def performed_job_count(job_class, args: nil)
    jobs = performed_jobs.select { |job| job[0] == job_class.name }
    jobs = jobs.select { |job| job[1] == args } if args
    jobs.count
  end

  def find_job(job_class, args: nil, queue: nil)
    jobs = enqueued_jobs.select { |job| job[0] == job_class.name }
    jobs = jobs.select { |job| job[2] == queue } if queue
    jobs = jobs.select { |job| job[1] == args } if args
    jobs.first
  end

  def job_exists?(job_class, args: nil, queue: nil)
    job_count(job_class, args: args, queue: queue) > 0
  end

  # Sync-specific job helpers
  def start_email_sync(email_account = nil, sync_session = nil)
    email_account ||= create(:email_account)
    sync_session ||= create(:sync_session)

    ProcessEmailsJob.perform_later(email_account.id, sync_session.id)
  end

  def simulate_email_processing(email_account, emails_count = 10)
    emails = emails_count.times.map do |i|
      "Compra realizada por $#{1000 + i * 100}.50 en Tienda #{i + 1} el #{Date.current.strftime('%d/%m/%Y')}"
    end

    ProcessEmailJob.perform_later(email_account.id, emails)
  end

  def assert_sync_jobs_enqueued(email_accounts)
    email_accounts.each do |account|
      expect(job_exists?(ProcessEmailsJob, args: [ account.id, anything ])).to be true
    end
  end

  def assert_monitoring_job_scheduled(sync_session, at_time: nil)
    at_time ||= 30.seconds.from_now

    assert_job_enqueued(SyncSessionMonitorJob,
                       args: [ sync_session.id ],
                       at: at_time)
  end

  # Job failure and retry testing
  def simulate_job_failure(job_class, error_class = StandardError, message = "Test error")
    allow_any_instance_of(job_class).to receive(:perform).and_raise(error_class, message)
  end

  def assert_job_retried(job_class, max_retries: 5)
    initial_attempts = performed_job_count(job_class)

    simulate_job_failure(job_class)

    expect {
      perform_enqueued_jobs
    }.to raise_error(StandardError, "Test error")

    final_attempts = performed_job_count(job_class)
    expect(final_attempts - initial_attempts).to be <= max_retries
  end

  def assert_job_not_retried_when_cancelled(job_class)
    job = enqueued_jobs.find { |j| j[0] == job_class.name }
    expect(job).to be_present

    # Cancel the job (implementation depends on your setup)
    if defined?(SolidQueue::Job)
      solid_job = SolidQueue::Job.find_by(class_name: job_class.name)
      solid_job&.destroy
    end

    simulate_job_failure(job_class)

    expect {
      perform_enqueued_jobs
    }.not_to raise_error

    expect(performed_job_count(job_class)).to eq(0)
  end

  # Job performance testing
  def measure_job_performance(job_class, *args)
    start_time = Time.current
    start_memory = memory_usage_mb

    job_class.perform_now(*args)

    end_time = Time.current
    end_memory = memory_usage_mb

    {
      execution_time: end_time - start_time,
      memory_used: end_memory - start_memory
    }
  end

  def assert_job_performance(job_class, *args, max_time: 30.seconds, max_memory: 100)
    performance = measure_job_performance(job_class, *args)

    expect(performance[:execution_time]).to be < max_time,
      "Job #{job_class} took #{performance[:execution_time]}s, expected under #{max_time}s"

    expect(performance[:memory_used]).to be < max_memory,
      "Job #{job_class} used #{performance[:memory_used]}MB, expected under #{max_memory}MB"

    performance
  end

  # Concurrent job testing
  def run_concurrent_jobs(job_class, args_list, max_workers: 3)
    results = []
    errors = []

    threads = args_list.in_groups_of(max_workers, false).flat_map do |group|
      group.map do |args|
        Thread.new do
          begin
            start_time = Time.current
            job_class.perform_now(*args)
            end_time = Time.current
            results << { args: args, time: end_time - start_time, success: true }
          rescue StandardError => e
            errors << { args: args, error: e.message }
          end
        end
      end
    end

    threads.each(&:join)

    {
      successful_jobs: results,
      failed_jobs: errors,
      success_rate: results.length.to_f / args_list.length,
      avg_execution_time: results.map { |r| r[:time] }.sum / results.length
    }
  end

  # Job monitoring helpers
  def wait_for_job_completion(job_class, args: nil, timeout: 30.seconds)
    start_time = Time.current

    loop do
      break if performed_job_count(job_class, args: args) > 0

      if Time.current - start_time > timeout
        raise "Job #{job_class} did not complete within #{timeout} seconds"
      end

      sleep 0.1
    end
  end

  def wait_for_all_jobs_completion(timeout: 60.seconds)
    start_time = Time.current

    loop do
      break if enqueued_jobs.empty?

      if Time.current - start_time > timeout
        remaining_jobs = enqueued_jobs.map { |job| job[0] }.join(', ')
        raise "Jobs did not complete within #{timeout} seconds. Remaining: #{remaining_jobs}"
      end

      perform_enqueued_jobs
      sleep 0.5
    end
  end

  private

  def memory_usage_mb
    (GC.stat[:heap_allocated_pages] * GC.stat[:heap_allocated_slots] * 40.0) / (1024 * 1024)
  end
end

# Custom matchers for job testing
RSpec::Matchers.define :have_enqueued_job do |job_class|
  chain :with_args do |*args|
    @args = args
  end

  chain :on_queue do |queue|
    @queue = queue
  end

  chain :at do |time|
    @at = time
  end

  supports_block_expectations

  match do |block|
    initial_count = job_count(job_class, args: @args, queue: @queue)
    block.call
    final_count = job_count(job_class, args: @args, queue: @queue)

    job_enqueued = final_count > initial_count

    if job_enqueued && @at
      job = find_job(job_class, args: @args, queue: @queue)
      job && job[:at] && (job[:at] - @at).abs <= 1
    else
      job_enqueued
    end
  end

  failure_message do
    "Expected #{job_class} to be enqueued#{@args ? " with args #{@args}" : ""}#{@queue ? " on queue #{@queue}" : ""}#{@at ? " at #{@at}" : ""}"
  end

  failure_message_when_negated do
    "Expected #{job_class} not to be enqueued#{@args ? " with args #{@args}" : ""}"
  end
end

RSpec::Matchers.define :have_performed_job do |job_class|
  chain :with_args do |*args|
    @args = args
  end

  supports_block_expectations

  match do |block|
    initial_count = performed_job_count(job_class, args: @args)

    begin
      block.call
      perform_enqueued_jobs
    rescue StandardError
      # Job might fail, but we still want to check if it was attempted
    end

    final_count = performed_job_count(job_class, args: @args)
    final_count > initial_count
  end

  failure_message do
    "Expected #{job_class} to be performed#{@args ? " with args #{@args}" : ""}"
  end
end

# Include job helpers in relevant specs
RSpec.configure do |config|
  config.include JobHelpers, type: :job
  config.include JobHelpers, type: :service

  # Set up job testing environment
  config.before(:suite) do
    # Configure test adapter for jobs
    ActiveJob::Base.queue_adapter = :test
  end

  config.around(:each, type: :job) do |example|
    # Ensure clean job state for each test
    perform_enqueued_jobs # Clear any existing jobs
    clear_enqueued_jobs
    clear_performed_jobs

    example.run
  end
end
