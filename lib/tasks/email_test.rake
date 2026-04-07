# frozen_string_literal: true

namespace :email do
  desc "Test email connection and configuration"
  task test_connection: :environment do
    puts "Testing Email Sync Configuration"
    puts "=" * 50

    # Check email accounts
    puts "\nEmail Accounts:"
    if EmailAccount.count == 0
      puts "  No email accounts found!"
      puts "  Please create an email account first"
      exit
    end

    EmailAccount.find_each do |account|
      puts "  - #{account.email} (#{account.provider}) - #{account.active? ? 'Active' : 'Inactive'}"
      puts "    Bank: #{account.bank_name}"
      puts "    IMAP: #{account.imap_server}:#{account.imap_port}"
      puts "    OAuth: #{account.oauth_configured? ? 'Yes' : 'No'}"
      puts "    Password: #{account.encrypted_password.present? ? 'Set' : 'Not set'}"
    end

    # Check service loading
    puts "\nService Loading:"
    begin
      Services::EmailProcessing::Fetcher
      puts "  Services::EmailProcessing::Fetcher loaded successfully"
    rescue NameError => e
      puts "  Failed to load service: #{e.message}"
      exit
    end

    # Check categorization engine
    puts "\nCategorization Engine:"
    begin
      Services::Categorization::Engine.create
      puts "  Categorization engine initialized"
    rescue => e
      puts "  Failed to initialize: #{e.message}"
    end

    # Development mode info
    if Rails.env.development?
      puts "\nDevelopment Mode Notes:"
      puts "  - Email sync requires valid IMAP credentials"
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
