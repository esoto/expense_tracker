# frozen_string_literal: true

require "rails_helper"

# Unit tests for PostgresBackupJob.
#
# All subprocess execution (pg_dump, gpg) and network I/O (net-sftp) are
# stubbed so the suite runs without a Postgres server, GPG binary, or a
# reachable Storage Box.
#
# Design: the before block stubs everything to a "happy path" default.
# Individual tests override the stub and/or assert against captured call args.
RSpec.describe PostgresBackupJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  # ── shared fake objects ───────────────────────────────────────────────────

  let(:fake_sftp_dir) do
    # double: glob yields nothing (empty Storage Box) by default
    dbl = double("Net::SFTP::Operations::Dir")  # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:glob)
    dbl
  end

  let(:sftp_session) do
    # Use plain double — Net::SFTP::Session doesn't expose mkdir_p!.
    # Our job implements sftp_mkdir_p as a helper that calls mkdir! per segment.
    dbl = double("Net::SFTP::Session")  # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:mkdir!).and_return(nil)
    allow(dbl).to receive(:upload!)
    allow(dbl).to receive(:dir).and_return(fake_sftp_dir)
    allow(dbl).to receive(:remove!)
    dbl
  end

  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:frozen_time) { Time.zone.parse("2026-05-01T02:00:00Z") }

  # Captured call args — populated by the before-block stubs
  let(:pg_dump_call_args) { [] }
  let(:gpg_call_args)     { [] }
  let(:sftp_upload_args)  { [] }

  before do
    travel_to(frozen_time)

    # Credentials
    allow(Rails.application.credentials).to receive(:dig)
      .with(:backup, :gpg_passphrase)
      .and_return("test-passphrase-from-credentials")

    # Required Storage Box env vars
    stub_const("ENV", ENV.to_hash.merge(
      "STORAGE_BOX_HOST"    => "u000000.your-storagebox.de",
      "STORAGE_BOX_USER"    => "u000000",
      "STORAGE_BOX_SSH_KEY" => "/run/secrets/storage_box_key"
    ))

    # Capture pg_dump call args
    allow(Open3).to receive(:capture3)
      .with(hash_including("PGPASSWORD"), a_string_starting_with("pg_dump")) do |env_hash, cmd|
        pg_dump_call_args.replace([ env_hash, cmd ])
        [ "", "", ok_status ]
      end

    # Capture gpg call args
    allow(Open3).to receive(:capture3)
      .with(a_string_including("gpg")) do |cmd|
        gpg_call_args.replace([ cmd ])
        [ "", "", ok_status ]
      end

    # Capture SFTP upload args
    allow(sftp_session).to receive(:upload!) do |local, remote|
      sftp_upload_args.replace([ local, remote ])
    end

    # SFTP.start
    allow(Net::SFTP).to receive(:start).and_yield(sftp_session)

    # Tempfile for passphrase
    fake_tf = instance_double(Tempfile,
      path: "/tmp/fake_pass_file",
      close!: nil, write: nil, flush: nil, chmod: nil)
    allow(Tempfile).to receive(:new).with("gpg_passphrase").and_return(fake_tf)

    # FileUtils.rm_f
    allow(FileUtils).to receive(:rm_f)
  end

  after { travel_back }

  # ── job configuration ────────────────────────────────────────────────────

  describe "job configuration" do
    it "uses the low-priority queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  # ── pg_dump command composition ──────────────────────────────────────────

  describe "pg_dump command composition" do
    before { job.perform }

    it "passes PGPASSWORD via the Open3 env hash (never on the command line)" do
      expect(pg_dump_call_args[0]).to include("PGPASSWORD")
    end

    it "does NOT embed PGPASSWORD in the command string" do
      expect(pg_dump_call_args[1]).not_to include("PGPASSWORD")
    end

    it "uses --format=custom" do
      expect(pg_dump_call_args[1]).to include("--format=custom")
    end

    it "uses --no-owner" do
      expect(pg_dump_call_args[1]).to include("--no-owner")
    end

    it "uses --no-acl" do
      expect(pg_dump_call_args[1]).to include("--no-acl")
    end

    it "targets expense_tracker_production" do
      expect(pg_dump_call_args[1]).to include("expense_tracker_production")
    end

    it "raises BackupError when pg_dump exits non-zero" do
      bad_status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3)
        .with(hash_including("PGPASSWORD"), a_string_starting_with("pg_dump"))
        .and_return([ "", "connection refused", bad_status ])

      expect { job.perform }.to raise_error(PostgresBackupJob::BackupError, /pg_dump failed/)
    end
  end

  # ── GPG encryption command composition ───────────────────────────────────

  describe "GPG encryption command composition" do
    before { job.perform }

    it "invokes gpg" do
      expect(gpg_call_args[0]).to include("gpg")
    end

    it "uses --symmetric" do
      expect(gpg_call_args[0]).to include("--symmetric")
    end

    it "uses AES256 cipher" do
      expect(gpg_call_args[0]).to include("AES256")
    end

    it "uses --batch (non-interactive)" do
      expect(gpg_call_args[0]).to include("--batch")
    end

    it "passes passphrase via --passphrase-file (not on command line)" do
      expect(gpg_call_args[0]).to include("--passphrase-file")
      expect(gpg_call_args[0]).not_to include("test-passphrase-from-credentials")
    end

    it "raises BackupError when gpg exits non-zero" do
      bad_status = instance_double(Process::Status, success?: false, exitstatus: 2)
      allow(Open3).to receive(:capture3)
        .with(a_string_including("gpg"))
        .and_return([ "", "gpg: error", bad_status ])

      expect { job.perform }.to raise_error(PostgresBackupJob::BackupError, /gpg encryption failed/)
    end
  end

  # ── SFTP upload path ─────────────────────────────────────────────────────

  describe "SFTP upload path" do
    # frozen_time is 2026-05-01T02:00:00Z
    before { job.perform }

    it "uploads to the correct YYYY/MM path" do
      expect(sftp_upload_args[1]).to match(
        %r{expense-tracker/2026/05/expense_tracker_production-20260501T020000Z\.dump\.gpg\z}
      )
    end

    it "creates the remote directory structure before uploading" do
      # sftp_mkdir_p calls mkdir! once per path segment.
      # "expense-tracker/2026/05" → 3 segments → at least 3 mkdir! calls.
      expect(sftp_session).to have_received(:mkdir!).at_least(3).times
    end

    it "connects to the configured Storage Box host" do
      # Net::SFTP.start is called twice per perform: once for upload, once for
      # the retention pass. Both must use the configured credentials.
      expect(Net::SFTP).to have_received(:start).with(
        "u000000.your-storagebox.de",
        "u000000",
        hash_including(keys: [ "/run/secrets/storage_box_key" ])
      ).at_least(:once)
    end
  end

  # ── retention policy (unit-tested directly via #send) ────────────────────

  describe "#files_to_delete (retention policy)" do
    # Build synthetic filenames spanning multiple months.
    def filename_for(time)
      "expense_tracker_production-#{time.utc.strftime('%Y%m%dT%H%M%SZ')}.dump.gpg"
    end

    around { |e| travel_to(Time.zone.parse("2026-05-15T02:00:00Z")) { e.run } }

    let(:now) { Time.now.utc }

    # 35 daily backups going back from now (index 0 = today, 34 = 35 days ago)
    let(:daily_files) do
      (0..34).map { |n| filename_for(now - n.days) }
    end

    # first-of-month anchors going back 14 months
    let(:monthly_files) do
      (1..14).map { |n| filename_for(now.beginning_of_month - n.months) }
    end

    let(:all_files) { (daily_files + monthly_files).uniq }

    subject(:to_delete) { job.send(:files_to_delete, all_files) }

    it "returns an Array" do
      expect(to_delete).to be_an(Array)
    end

    it "keeps the most recent 30 daily backups" do
      daily_files.first(30).each do |f|
        expect(to_delete).not_to include(f), "#{f} should be kept (within 30-day daily window)"
      end
    end

    it "deletes daily backups older than 30 days that are not monthly anchors" do
      old_dailies = daily_files[30..].reject do |f|
        # Monthly anchors on the 1st of the month are kept regardless of age.
        # Filename format: expense_tracker_production-YYYYMMDDTHHMMSSZ.dump.gpg
        m = f.match(/(\d{4})(\d{2})(\d{2})T/)
        m && m[3].to_i == 1
      end
      old_dailies.each do |f|
        expect(to_delete).to include(f), "#{f} should be deleted (>30 days, not monthly anchor)"
      end
    end

    it "keeps first-of-month files within the 12-month window" do
      monthly_files.first(12).each do |f|
        expect(to_delete).not_to include(f), "#{f} should be kept (within 12-month monthly window)"
      end
    end

    it "deletes first-of-month files outside the 12-month window" do
      monthly_files[12..].each do |f|
        expect(to_delete).to include(f), "#{f} should be deleted (outside 12-month monthly window)"
      end
    end

    it "never deletes a file that is within the 30-day window" do
      daily_files.first(30).each do |f|
        expect(to_delete).not_to include(f)
      end
    end
  end

  # ── GPG passphrase resolution ─────────────────────────────────────────────

  describe "GPG passphrase resolution" do
    it "falls back to BACKUP_GPG_PASSPHRASE env var when credentials return nil" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:backup, :gpg_passphrase).and_return(nil)
      stub_const("ENV", ENV.to_hash.merge(
        "STORAGE_BOX_HOST"      => "u000000.your-storagebox.de",
        "STORAGE_BOX_USER"      => "u000000",
        "STORAGE_BOX_SSH_KEY"   => "/run/secrets/storage_box_key",
        "BACKUP_GPG_PASSPHRASE" => "env-passphrase"
      ))

      expect { job.perform }.not_to raise_error
    end

    it "raises BackupError when neither credentials nor ENV provides a passphrase" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:backup, :gpg_passphrase).and_return(nil)
      stub_const("ENV", ENV.to_hash.merge(
        "STORAGE_BOX_HOST"    => "u000000.your-storagebox.de",
        "STORAGE_BOX_USER"    => "u000000",
        "STORAGE_BOX_SSH_KEY" => "/run/secrets/storage_box_key"
      ).except("BACKUP_GPG_PASSPHRASE"))

      expect { job.perform }.to raise_error(PostgresBackupJob::BackupError, /passphrase/)
    end
  end

  # ── temp file cleanup ─────────────────────────────────────────────────────

  describe "temp file cleanup" do
    it "removes local dump and encrypted files after uploading" do
      job.perform
      expect(FileUtils).to have_received(:rm_f).at_least(2).times
    end
  end
end
