# frozen_string_literal: true

# lib/tasks/postgres_backup.rake
#
# Operator tasks for the nightly Postgres backup pipeline (PER-527).
#
# Usage:
#   bin/rails postgres_backup:run_now          # kick off a backup immediately
#   bin/rails postgres_backup:list_remote      # list what's in the Storage Box
#   bin/rails postgres_backup:restore[FILE]    # download + decrypt a backup
#
# All tasks require STORAGE_BOX_HOST, STORAGE_BOX_USER, STORAGE_BOX_SSH_KEY,
# and either Rails.application.credentials.backup.gpg_passphrase or
# BACKUP_GPG_PASSPHRASE to be set.

namespace :postgres_backup do
  desc "Run a Postgres backup immediately (same as the nightly job)"
  task run_now: :environment do
    puts "[postgres_backup:run_now] Starting backup..."
    PostgresBackupJob.perform_now
    puts "[postgres_backup:run_now] Done."
  end

  desc "List remote backup files in the Hetzner Storage Box"
  task list_remote: :environment do
    require "net/sftp"

    host     = ENV.fetch("STORAGE_BOX_HOST") { abort "STORAGE_BOX_HOST not set" }
    user     = ENV.fetch("STORAGE_BOX_USER") { abort "STORAGE_BOX_USER not set" }
    key_path = ENV.fetch("STORAGE_BOX_SSH_KEY") { abort "STORAGE_BOX_SSH_KEY not set" }

    puts "[postgres_backup:list_remote] Connecting to #{host}..."

    files = []
    Net::SFTP.start(host, user, keys: [ key_path ]) do |sftp|
      sftp.dir.glob("expense-tracker/*/*", "expense_tracker_production-*.dump.gpg") do |entry|
        files << entry.name
      end
    end

    if files.empty?
      puts "  (no backups found)"
    else
      files.sort.each { |f| puts "  #{f}" }
      puts "\nTotal: #{files.size} backup(s)"
    end
  end

  # rubocop:disable Metrics/BlockLength
  desc "Download and decrypt a remote backup. Usage: bin/rails 'postgres_backup:restore[FILENAME]'"
  task :restore, [ :filename ] => :environment do |_t, args|
    require "net/sftp"
    require "tempfile"
    require "open3"

    filename = args[:filename]
    abort "Usage: bin/rails 'postgres_backup:restore[FILENAME]'" if filename.blank?

    # Resolve credentials
    passphrase = Rails.application.credentials.dig(:backup, :gpg_passphrase) ||
                 ENV["BACKUP_GPG_PASSPHRASE"]
    abort "No GPG passphrase — set credentials.backup.gpg_passphrase or BACKUP_GPG_PASSPHRASE" if passphrase.blank?

    host     = ENV.fetch("STORAGE_BOX_HOST") { abort "STORAGE_BOX_HOST not set" }
    user     = ENV.fetch("STORAGE_BOX_USER") { abort "STORAGE_BOX_USER not set" }
    key_path = ENV.fetch("STORAGE_BOX_SSH_KEY") { abort "STORAGE_BOX_SSH_KEY not set" }

    # Derive the remote path from the filename
    m = filename.match(/(\d{4})(\d{2})\d{2}T/)
    abort "Cannot parse YYYY/MM from filename: #{filename}" unless m
    remote_path = "expense-tracker/#{m[1]}/#{m[2]}/#{filename}"

    local_gpg  = File.join(Dir.pwd, filename)
    local_dump = local_gpg.sub(/\.gpg\z/, "")

    puts "[postgres_backup:restore] Downloading #{remote_path}..."
    Net::SFTP.start(host, user, keys: [ key_path ]) do |sftp|
      sftp.download!(remote_path, local_gpg)
    end
    puts "  Saved to: #{local_gpg}"

    puts "[postgres_backup:restore] Decrypting..."
    passphrase_file = Tempfile.new("gpg_restore_pass")
    begin
      passphrase_file.write(passphrase)
      passphrase_file.flush
      passphrase_file.chmod(0o600)

      cmd = [
        "gpg",
        "--batch",
        "--yes",
        "--passphrase-file #{passphrase_file.path}",
        "--output #{local_dump}",
        "--decrypt #{local_gpg}"
      ].join(" ")

      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        abort "gpg decryption failed (exit #{status.exitstatus}): #{stderr.presence || stdout}"
      end
    ensure
      passphrase_file.close!
    end

    File.delete(local_gpg)
    puts "  Decrypted dump: #{local_dump}"
    puts ""
    puts "To restore into a local database run:"
    puts "  pg_restore --clean --if-exists -d <DBNAME> #{local_dump}"
    puts ""
    puts "NOTE: this does NOT auto-load the dump. Run pg_restore manually and verify the result."
  end
  # rubocop:enable Metrics/BlockLength
end
