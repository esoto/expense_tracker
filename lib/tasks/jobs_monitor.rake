namespace :jobs do
  desc "Show background jobs dashboard"
  task dashboard: :environment do
    puts "🚀 SOLID QUEUE BACKGROUND JOBS - DASHBOARD"
    puts "=" * 60
    puts "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    puts

    # Queue Statistics
    puts "📊 QUEUE STATISTICS"
    puts "-" * 30
    puts "Total Jobs: #{SolidQueue::Job.count}"
    puts "Scheduled Jobs: #{SolidQueue::Job.where.not(scheduled_at: nil).count}"
    puts "Finished Jobs: #{SolidQueue::Job.where.not(finished_at: nil).count}"
    puts "Unfinished Jobs: #{SolidQueue::Job.where(finished_at: nil).count}"
    puts

    # Queue Breakdown by Queue Name
    puts "📋 JOBS BY QUEUE"
    puts "-" * 30
    queue_counts = SolidQueue::Job.group(:queue_name).count
    queue_counts.each do |queue, count|
      puts "#{queue}: #{count} jobs"
    end
    puts

    # Jobs by Class
    puts "🔧 JOBS BY TYPE"
    puts "-" * 30
    class_counts = SolidQueue::Job.group(:class_name).count.sort_by { |_, count| -count }.first(10)
    class_counts.each do |class_name, count|
      puts "#{class_name}: #{count} jobs"
    end
    puts

    # Recent Jobs
    puts "🕐 RECENT JOBS (Last 10)"
    puts "-" * 30
    recent_jobs = SolidQueue::Job.order(created_at: :desc).limit(10)
    recent_jobs.each do |job|
      status_icon = if job.finished_at.present?
                     "✅"
      elsif job.scheduled_at.present? && job.scheduled_at > Time.current
                     "⏳"
      else
                     "🏃"
      end

      puts "#{status_icon} #{job.class_name} (#{job.queue_name}) - #{job.created_at.strftime('%H:%M:%S')}"
    end
    puts

    # Worker Processes
    puts "🏃 WORKER PROCESSES"
    puts "-" * 30
    processes = SolidQueue::Process.all
    processes.each do |process|
      status = process.last_heartbeat_at&.> (30.seconds.ago) ? "✅ Active" : "❌ Stale"
      puts "#{process.name} - #{status}"
      puts "   Last heartbeat: #{process.last_heartbeat_at&.strftime('%H:%M:%S') || 'Never'}"
    end
    puts
  end

  desc "Live monitor for background jobs"
  task monitor: :environment do
    puts "🚀 SOLID QUEUE JOBS - LIVE MONITOR"
    puts "=" * 60
    puts "Press Ctrl+C to stop monitoring"
    puts

    loop do
      begin
        # Clear screen
        system("clear") || system("cls")

        puts "🚀 SOLID QUEUE JOBS - LIVE MONITOR"
        puts "=" * 60
        puts "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
        puts

        # Queue Statistics
        puts "📊 QUEUE STATISTICS"
        puts "-" * 30
        total = SolidQueue::Job.count
        finished = SolidQueue::Job.where.not(finished_at: nil).count
        unfinished = SolidQueue::Job.where(finished_at: nil).count
        scheduled = SolidQueue::Job.where.not(scheduled_at: nil).where("scheduled_at > ?", Time.current).count

        puts "Total Jobs: #{total}"
        puts "Finished Jobs: #{finished}"
        puts "Active Jobs: #{unfinished}"
        puts "Scheduled Jobs: #{scheduled}"
        puts

        # Queue Breakdown
        puts "📋 ACTIVE QUEUES"
        puts "-" * 30
        active_queues = SolidQueue::Job.where(finished_at: nil).group(:queue_name).count
        if active_queues.any?
          active_queues.each do |queue, count|
            puts "#{queue}: #{count} active"
          end
        else
          puts "No active jobs"
        end
        puts

        # Recent Jobs
        recent_jobs = SolidQueue::Job.order(created_at: :desc).limit(5)
        if recent_jobs.any?
          puts "🕐 RECENT ACTIVITY"
          puts "-" * 30
          recent_jobs.each do |job|
            status = job.finished_at.present? ? "✅ Finished" : "🏃 Active"
            puts "#{status} #{job.class_name} - #{job.created_at.strftime('%H:%M:%S')}"
          end
          puts
        end

        # Worker Health
        puts "🏃 WORKER STATUS"
        puts "-" * 30
        processes = SolidQueue::Process.all
        processes.each do |process|
          status = process.last_heartbeat_at&.> (30.seconds.ago) ? "✅" : "❌"
          puts "#{status} #{process.name}"
        end
        puts

        puts "🔄 Refreshing in 5 seconds... (Ctrl+C to stop)"

        # Wait for 5 seconds
        sleep 5

      rescue Interrupt
        puts "\n\n👋 Monitor stopped by user"
        break
      rescue => e
        puts "\n❌ Error: #{e.message}"
        puts "Retrying in 10 seconds..."
        sleep 10
      end
    end
  end

  desc "Show job statistics"
  task stats: :environment do
    puts "📊 SOLID QUEUE STATISTICS"
    puts "=" * 40

    total = SolidQueue::Job.count
    finished = SolidQueue::Job.where.not(finished_at: nil).count
    active = SolidQueue::Job.where(finished_at: nil).count
    scheduled = SolidQueue::Job.where.not(scheduled_at: nil).where("scheduled_at > ?", Time.current).count

    puts "Total: #{total}"
    puts "Finished: #{finished} (#{(finished.to_f / total * 100).round(1)}%)" if total > 0
    puts "Active: #{active} (#{(active.to_f / total * 100).round(1)}%)" if total > 0
    puts "Scheduled: #{scheduled} (#{(scheduled.to_f / total * 100).round(1)}%)" if total > 0
  end

  desc "Clear finished jobs (older than 1 day)"
  task cleanup: :environment do
    puts "🧹 CLEANING UP OLD JOBS"
    puts "=" * 30

    old_jobs = SolidQueue::Job.where("finished_at < ?", 1.day.ago).where.not(finished_at: nil)
    count = old_jobs.count

    if count > 0
      old_jobs.delete_all
      puts "✅ Deleted #{count} old finished jobs"
    else
      puts "✅ No old jobs to clean up"
    end
  end
end
