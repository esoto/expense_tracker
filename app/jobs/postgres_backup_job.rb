# frozen_string_literal: true

require "open3"
require "tempfile"
require "fileutils"
require "net/sftp"

# PostgresBackupJob — nightly off-host Postgres backup to Hetzner Storage Box.
#
# Scheduled at 02:00 UTC daily via config/recurring.yml.
#
# Pipeline:
#   1. pg_dump --format=custom --no-owner --no-acl → /tmp/<timestamp>.dump
#   2. GPG symmetric encryption (AES256) with passphrase from credentials
#   3. SFTP upload to Storage Box: /expense-tracker/YYYY/MM/<filename>.dump.gpg
#   4. Retention: keep 30 daily + first-of-month for 12 months, delete rest
#
# External dependencies (must be installed on the app host):
#   - pg_dump   (postgresql-client)
#   - gpg       (gnupg)
#
# Required credentials/env vars:
#   - Rails.application.credentials.dig(:backup, :gpg_passphrase)   OR  BACKUP_GPG_PASSPHRASE
#   - STORAGE_BOX_HOST   — Hetzner Storage Box hostname (e.g. u123456.your-storagebox.de)
#   - STORAGE_BOX_USER   — Storage Box SSH username
#   - STORAGE_BOX_SSH_KEY — Path to private key file (e.g. /run/secrets/storage_box_key)
#
# The production Postgres host is personal-blog-db (internal Hetzner network).
# PGPASSWORD is passed via Open3 env hash so it never appears on the command line.
class PostgresBackupJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Raised on any unrecoverable backup step failure.
  class BackupError < StandardError; end

  # Remote root directory inside the Storage Box.
  REMOTE_ROOT = "expense-tracker"

  # ── public entry point ───────────────────────────────────────────────────

  def perform
    timestamp  = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    base_name  = "expense_tracker_production-#{timestamp}"
    dump_path  = File.join(Dir.tmpdir, "#{base_name}.dump")
    gpg_path   = "#{dump_path}.gpg"

    Rails.logger.info "[PostgresBackup] Starting backup (timestamp=#{timestamp})"

    begin
      run_pg_dump(dump_path)
      run_gpg_encrypt(dump_path, gpg_path)
      sftp_upload(gpg_path, remote_path(timestamp))
      apply_retention
    ensure
      FileUtils.rm_f(dump_path)
      FileUtils.rm_f(gpg_path)
    end

    Rails.logger.info "[PostgresBackup] Backup complete (timestamp=#{timestamp})"
  rescue BackupError => e
    Rails.logger.error "[PostgresBackup] Backup failed: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "[PostgresBackup] Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  # ── pg_dump ──────────────────────────────────────────────────────────────

  def run_pg_dump(output_path)
    Rails.logger.info "[PostgresBackup] Running pg_dump → #{output_path}"

    cmd = [
      "pg_dump",
      "--format=custom",
      "--no-owner",
      "--no-acl",
      "--host=#{pg_host}",
      "--port=#{pg_port}",
      "--username=#{pg_user}",
      "--file=#{output_path}",
      pg_database
    ].join(" ")

    env = { "PGPASSWORD" => pg_password }

    stdout, stderr, status = Open3.capture3(env, cmd)

    return if status.success?

    raise BackupError, "pg_dump failed (exit #{status.exitstatus}): #{stderr.presence || stdout}"
  end

  # ── GPG symmetric encryption ─────────────────────────────────────────────

  def run_gpg_encrypt(input_path, output_path)
    Rails.logger.info "[PostgresBackup] Encrypting with GPG → #{output_path}"

    passphrase = resolve_gpg_passphrase

    passphrase_file = Tempfile.new("gpg_passphrase")
    begin
      passphrase_file.write(passphrase)
      passphrase_file.flush
      passphrase_file.chmod(0o600)

      cmd = [
        "gpg",
        "--batch",
        "--yes",
        "--symmetric",
        "--cipher-algo AES256",
        "--passphrase-file #{passphrase_file.path}",
        "--output #{output_path}",
        input_path
      ].join(" ")

      stdout, stderr, status = Open3.capture3(cmd)

      return if status.success?

      raise BackupError, "gpg encryption failed (exit #{status.exitstatus}): #{stderr.presence || stdout}"
    ensure
      passphrase_file.close!
    end
  end

  # ── SFTP upload ───────────────────────────────────────────────────────────

  def sftp_upload(local_path, remote_file_path)
    remote_dir = File.dirname(remote_file_path)
    Rails.logger.info "[PostgresBackup] Uploading via SFTP → #{sftp_host}:#{remote_file_path}"

    Net::SFTP.start(sftp_host, sftp_user, keys: [ sftp_key_path ]) do |sftp|
      sftp_mkdir_p(sftp, remote_dir)
      sftp.upload!(local_path, remote_file_path)
    end
  end

  # Recursively create a remote directory path (equivalent to mkdir -p).
  # Ignores "already exists" errors so re-runs are idempotent.
  def sftp_mkdir_p(sftp, path)
    segments = path.split("/").reject(&:empty?)
    segments.each_with_index do |_seg, idx|
      partial = segments[0..idx].join("/")
      partial = "/#{partial}" if path.start_with?("/")
      sftp.mkdir!(partial)
    rescue Net::SFTP::StatusException => e
      # FX_FAILURE (4) is returned when the directory already exists on many
      # SFTP servers. FX_PERMISSION_DENIED (3) can also appear on the root.
      # Re-raise for any other error code.
      raise unless e.code == Net::SFTP::Constants::StatusCodes::FX_FAILURE ||
                   e.code == Net::SFTP::Constants::StatusCodes::FX_PERMISSION_DENIED
    end
  end

  # ── retention policy ──────────────────────────────────────────────────────

  # Retention rules (applied after each backup):
  #   - DAILY:   keep all files whose timestamp is within the last 30 days
  #   - MONTHLY: keep the first backup of each calendar month for the last 12 months
  #   - DELETE:  everything else
  #
  # Retention is evaluated on the remote filename which encodes the timestamp
  # as YYYYMMDDTHHMMSSZ — lexicographic sort is chronological sort.
  def apply_retention
    Rails.logger.info "[PostgresBackup] Applying retention policy"

    Net::SFTP.start(sftp_host, sftp_user, keys: [ sftp_key_path ]) do |sftp|
      all_files = list_remote_files(sftp)
      to_delete = files_to_delete(all_files)

      to_delete.each do |filename|
        remote_path = "#{REMOTE_ROOT}/#{remote_year_month(filename)}/#{filename}"
        sftp.remove!(remote_path)
        Rails.logger.info "[PostgresBackup] Deleted #{remote_path}"
      end

      Rails.logger.info "[PostgresBackup] Retention: kept #{all_files.size - to_delete.size}, deleted #{to_delete.size}"
    end
  rescue StandardError => e
    # Retention failure is not fatal — the backup itself succeeded.
    Rails.logger.error "[PostgresBackup] Retention pass failed (non-fatal): #{e.message}"
  end

  # Returns the list of remote filenames (basename only) that should be deleted.
  # Exposed as a non-private method so specs can call it via `send`.
  #
  # Keep set (union):
  #   - Any file whose parsed timestamp is within 30 days of now (daily window)
  #   - The oldest file per calendar-month key where that month is within 12
  #     months of the current month start (monthly anchor)
  def files_to_delete(all_files)
    now            = Time.now.utc
    daily_cutoff   = now - 30.days
    monthly_cutoff = (now.beginning_of_month - 12.months)

    keep = Set.new

    # Build a month → files map for monthly anchor selection
    by_month = all_files.group_by { |f| remote_year_month(f) }

    by_month.each do |_month_key, files|
      sorted = files.sort # lexicographic = chronological for our filename format
      anchor = sorted.first
      # Parse the anchor timestamp; keep if within 12-month window
      ts = parse_filename_timestamp(anchor)
      keep << anchor if ts && ts.beginning_of_month >= monthly_cutoff
    end

    all_files.each_with_object([]) do |filename, deletes|
      ts = parse_filename_timestamp(filename)
      next if ts.nil? # malformed filename — leave it alone

      # Within 30-day daily window?
      next keep << filename if ts >= daily_cutoff

      # Already in the monthly keep set?
      next if keep.include?(filename)

      deletes << filename
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  # Builds the full remote path for a given timestamp string.
  # e.g. "expense-tracker/2026/05/expense_tracker_production-20260501T020000Z.dump.gpg"
  def remote_path(timestamp)
    year  = timestamp[0, 4]
    month = timestamp[4, 2]
    "#{REMOTE_ROOT}/#{year}/#{month}/expense_tracker_production-#{timestamp}.dump.gpg"
  end

  # Returns YYYY/MM from a backup filename.
  def remote_year_month(filename)
    m = filename.match(/(\d{4})(\d{2})\d{2}T\d{6}Z/)
    m ? "#{m[1]}/#{m[2]}" : "unknown"
  end

  # Parses the timestamp embedded in a backup filename.
  def parse_filename_timestamp(filename)
    m = filename.match(/(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z/)
    return nil unless m

    Time.utc(m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, m[6].to_i)
  end

  # Lists all backup filenames across all YYYY/MM subdirectories.
  def list_remote_files(sftp)
    files = []
    sftp.dir.glob("#{REMOTE_ROOT}/*/*", "expense_tracker_production-*.dump.gpg") do |entry|
      files << File.basename(entry.name)
    end
    files
  end

  # ── configuration accessors ───────────────────────────────────────────────

  def resolve_gpg_passphrase
    passphrase = Rails.application.credentials.dig(:backup, :gpg_passphrase) ||
                 ENV["BACKUP_GPG_PASSPHRASE"]

    raise BackupError, "No GPG passphrase configured — set credentials.backup.gpg_passphrase or BACKUP_GPG_PASSPHRASE" if passphrase.blank?

    passphrase
  end

  def pg_host
    ENV.fetch("POSTGRES_HOST", "personal-blog-db")
  end

  def pg_port
    ENV.fetch("POSTGRES_PORT", "5432")
  end

  def pg_user
    ENV.fetch("POSTGRES_USER", "expense_tracker")
  end

  def pg_password
    ENV.fetch("POSTGRES_PASSWORD", "")
  end

  def pg_database
    "expense_tracker_production"
  end

  def sftp_host
    ENV.fetch("STORAGE_BOX_HOST") do
      raise BackupError, "STORAGE_BOX_HOST is not set — configure it in .kamal/secrets"
    end
  end

  def sftp_user
    ENV.fetch("STORAGE_BOX_USER") do
      raise BackupError, "STORAGE_BOX_USER is not set — configure it in .kamal/secrets"
    end
  end

  def sftp_key_path
    ENV.fetch("STORAGE_BOX_SSH_KEY") do
      raise BackupError, "STORAGE_BOX_SSH_KEY is not set — configure it in .kamal/secrets"
    end
  end
end
