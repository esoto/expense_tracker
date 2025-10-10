# frozen_string_literal: true

namespace :email do
  desc "Diagnostic sync with detailed timing"
  task :sync_diagnostic, [ :year_month ] => :environment do |task, args|
    require "benchmark"

    year_month = args[:year_month] || Date.current.strftime("%Y-%m")
    date = Date.parse("#{year_month}-01")

    EmailAccount.active.find_each do |account|
      puts "\n🔍 Diagnostic sync for #{account.email}"

      service = Email::ProcessingService.new(account, {
        auto_categorize: false,  # Disable to isolate fetch issues
        limit: 10  # Start small
      })

      # Test phases separately
      phases = {}

      phases[:connection] = Benchmark.measure do
        result = service.test_connection
        puts "  Connection: #{result[:success] ? '✓' : '✗'}"
      end

      phases[:discovery] = Benchmark.measure do
        emails = []
        service.send(:with_imap_connection) do |imap|
          imap.examine("INBOX")
          ids = service.send(:search_for_transaction_emails, imap, date.beginning_of_month, date.end_of_month)
          puts "  Messages found: #{ids.count}"
        end
      end

      phases[:fetch_sample] = Benchmark.measure do
        # Test fetching just 3 messages to see timing
        service.send(:with_imap_connection) do |imap|
          imap.examine("INBOX")
          ids = service.send(:search_for_transaction_emails, imap, date.beginning_of_month, date.end_of_month)

          if ids.any?
            sample_ids = ids.first(3)
            puts "    Fetching sample messages: #{sample_ids.inspect}"
            fetch_data = imap.fetch(sample_ids, [ "RFC822", "UID", "FLAGS" ])
            puts "    Sample fetch (3 msgs): #{fetch_data.count} retrieved"

            # Check sizes
            total_size = 0
            fetch_data.each do |msg|
              size = msg.attr["RFC822"]&.bytesize || 0
              total_size += size
              puts "      Message UID #{msg.attr['UID']}: #{(size/1024.0).round(1)} KB"
            end
            puts "    Total sample size: #{(total_size/1024.0).round(1)} KB"
          end
        end
      end

      # Print timing report
      puts "\n  Timing Report:"
      phases.each do |phase, time|
        puts "    #{phase}: #{time.real.round(2)}s"
      end

      # Memory usage check
      puts "    Current memory usage: #{`ps -o rss= -p #{Process.pid}`.to_i / 1024} MB"
    end
  end
end
