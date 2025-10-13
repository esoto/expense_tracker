# frozen_string_literal: true

namespace :email do
  desc "Test email connection and configuration"
  task test_connection: :environment do
    puts "Testing Email Sync Configuration"
    puts "=" * 50

    # Check email accounts
    puts "\n📧 Email Accounts:"
    if EmailAccount.count == 0
      puts "  ❌ No email accounts found!"
      puts "  💡 Please create an email account first"
      exit
    end

    EmailAccount.find_each do |account|
      puts "  - #{account.email} (#{account.provider}) - #{account.active? ? '✅ Active' : '⚠️ Inactive'}"
      puts "    Bank: #{account.bank_name}"
      puts "    IMAP: #{account.imap_server}:#{account.imap_port}"
      puts "    OAuth: #{account.oauth_configured? ? 'Yes' : 'No'}"
      puts "    Password: #{account.encrypted_password.present? ? 'Set' : 'Not set'}"
    end

    # Check service loading
    puts "\n🔧 Service Loading:"
    begin
      service_class = Services::Email::ProcessingService
      puts "  ✅ Services::Email::ProcessingService loaded successfully"
    rescue NameError => e
      puts "  ❌ Failed to load service: #{e.message}"
      exit
    end

    # Check categorization engine
    puts "\n🤖 Categorization Engine:"
    begin
      engine = Services::Categorization::Engine.create
      puts "  ✅ Categorization engine initialized"
    rescue => e
      puts "  ❌ Failed to initialize: #{e.message}"
    end

    # Test connection for each active account
    puts "\n🔗 Testing Connections:"
    EmailAccount.active.find_each do |account|
      puts "\n  Testing #{account.email}..."

      begin
        service = Services::Email::ProcessingService.new(account)

        # Test connection with timeout
        result = Timeout.timeout(10) do
          service.test_connection
        end

        if result[:success]
          puts "    ✅ Connection successful!"
        else
          puts "    ❌ Connection failed: #{result[:message]}"

          # Common issues and solutions
          if result[:message].include?("password")
            puts "    💡 Check if password is correct or use OAuth"
          elsif result[:message].include?("IMAP")
            puts "    💡 Check IMAP settings or firewall"
          elsif result[:message].include?("SSL")
            puts "    💡 SSL/TLS configuration issue"
          end
        end
      rescue Timeout::Error
        puts "    ⏱️ Connection timeout - server might be unreachable"
        puts "    💡 Check network connection and IMAP server settings"
      rescue => e
        puts "    💥 Error: #{e.message}"
        puts "    💡 #{e.class.name}"
      end
    end

    # Development mode info
    if Rails.env.development?
      puts "\n📝 Development Mode Notes:"
      puts "  - Email sync will create sample data if connection fails"
      puts "  - Real IMAP connections require valid credentials"
      puts "  - Consider using OAuth for Gmail accounts"
    end

    puts "\n" + "=" * 50
    puts "Test complete!"
  end

  desc "Create sample email account for testing"
  task create_sample_account: :environment do
    email = "test@example.com"

    if EmailAccount.exists?(email: email)
      puts "Email account #{email} already exists"
    else
      EmailAccount.create!(
        email: email,
        provider: "manual",
        bank_name: "BAC",
        encrypted_password: "test_password",
        active: true,
        encrypted_settings: {
          imap: {
            server: "imap.example.com",
            port: 993
          }
        }.to_json
      )
      puts "Created sample email account: #{email}"
    end
  end
end
