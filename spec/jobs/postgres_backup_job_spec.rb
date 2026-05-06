# frozen_string_literal: true

require "rails_helper"

# Unit tests for PostgresBackupJob.
#
# All subprocess execution (pg_dump, gpg) and network I/O (net-sftp) are
# stubbed so the suite runs without a Postgres server, GPG binary, or a
# reachable Storage Box.
#
# Open3 is invoked in argv form (no /bin/sh), so stubs match on the first
# positional arg ("pg_dump" / "gpg") rather than a joined string.
RSpec.describe PostgresBackupJob, type: :job, unit: true do
  subject(:job) { described_class.new }

  # ── shared fake objects ───────────────────────────────────────────────────

  let(:fake_sftp_dir) do
    dbl = double("Net::SFTP::Operations::Dir")  # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:glob)
    dbl
  end

  let(:sftp_session) do
    # Net::SFTP::Session doesn't expose every method we stub here; plain
    # double avoids verifying-double false negatives.
    dbl = double("Net::SFTP::Session")  # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:mkdir!).and_return(nil)
    allow(dbl).to receive(:upload!)
    allow(dbl).to receive(:dir).and_return(fake_sftp_dir)
    allow(dbl).to receive(:remove!)
    dbl
  end

  let(:ok_status)  { instance_double(Process::Status, success?: true,  exitstatus: 0) }
  let(:bad_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:frozen_time) { Time.zone.parse("2026-05-01T02:00:00Z") }

  # Captured argv for assertions
  let(:pg_dump_call) { { env: nil, args: nil } }
  let(:gpg_call)     { { args: nil } }
  let(:sftp_upload)  { { local: nil, remote: nil } }

  before do
    travel_to(frozen_time)

    allow(Rails.application.credentials).to receive(:dig)
      .with(:backup, :gpg_passphrase)
      .and_return("test-passphrase-from-credentials")

    stub_const("ENV", ENV.to_hash.merge(
      "STORAGE_BOX_HOST"    => "u000000.your-storagebox.de",
      "STORAGE_BOX_USER"    => "u000000",
      "STORAGE_BOX_SSH_KEY" => "/run/secrets/storage_box_key"
    ))

    # Argv-form Open3.capture3:
    #   - pg_dump: capture3({env}, "pg_dump", "--format=custom", ..., db)
    #   - gpg:     capture3("gpg", "--batch", ...)
    allow(Open3).to receive(:capture3) do |*invocation|
      first = invocation.first
      if first.is_a?(Hash)
        pg_dump_call[:env]  = first
        pg_dump_call[:args] = invocation[1..]
      else
        gpg_call[:args] = invocation
      end
      [ "", "", ok_status ]
    end

    allow(sftp_session).to receive(:upload!) do |local, remote|
      sftp_upload[:local]  = local
      sftp_upload[:remote] = remote
    end

    allow(Net::SFTP).to receive(:start).and_yield(sftp_session)

    fake_tf = instance_double(Tempfile,
      path: "/tmp/fake_pass_file",
      close!: nil, write: nil, flush: nil, chmod: nil)
    allow(Tempfile).to receive(:new).with("gpg_passphrase").and_return(fake_tf)

    allow(FileUtils).to receive(:rm_f)

    # The job chmods + size-checks the dump file. Open3 is stubbed so the
    # file never actually exists; pretend it does and is large enough.
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:size?).and_call_original
    allow(File).to receive(:chmod).and_call_original
    allow(File).to receive(:exist?).with(/\.dump\z/).and_return(true)
    allow(File).to receive(:size?).with(/\.dump\z/).and_return(2_048)
    allow(File).to receive(:chmod).with(0o600, /\.dump\z/).and_return(0)

    # Cache write for last_success_at
    allow(Rails.cache).to receive(:write).and_call_original
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

    it "passes PGPASSWORD via the Open3 env hash (never as an argv element)" do
      expect(pg_dump_call[:env]).to include("PGPASSWORD")
      expect(pg_dump_call[:args]).not_to include(a_string_matching(/PGPASSWORD/))
    end

    it "invokes pg_dump in argv form (no shell)" do
      expect(pg_dump_call[:args].first).to eq("pg_dump")
    end

    it "uses --format=custom, --no-owner, --no-acl, --lock-wait-timeout" do
      expect(pg_dump_call[:args]).to include(
        "--format=custom", "--no-owner", "--no-acl", "--lock-wait-timeout=30000"
      )
    end

    it "targets expense_tracker_production" do
      expect(pg_dump_call[:args]).to include("expense_tracker_production")
    end

    it "raises BackupError when pg_dump exits non-zero" do
      allow(Open3).to receive(:capture3) do |*invocation|
        if invocation.first.is_a?(Hash)
          [ "", "connection refused", bad_status ]
        else
          [ "", "", ok_status ]
        end
      end

      expect { job.perform }.to raise_error(PostgresBackupJob::BackupError, /pg_dump failed/)
    end

    it "raises BackupError when pg_dump produces an empty/missing file" do
      allow(File).to receive(:size?).with(/\.dump\z/).and_return(0)

      expect { job.perform }.to raise_error(
        PostgresBackupJob::BackupError, /empty\/missing/
      )
    end

    it "chmods the dump to 0600 immediately after pg_dump" do
      expect(File).to have_received(:chmod).with(0o600, /\.dump\z/)
    end
  end

  # ── GPG encryption command composition ───────────────────────────────────

  describe "GPG encryption command composition" do
    before { job.perform }

    it "invokes gpg in argv form" do
      expect(gpg_call[:args].first).to eq("gpg")
    end

    it "uses --symmetric, --batch, AES256, --passphrase-file" do
      expect(gpg_call[:args]).to include(
        "--symmetric", "--batch", "AES256", "--passphrase-file"
      )
    end

    it "passes the passphrase tempfile path, not the passphrase itself" do
      expect(gpg_call[:args]).to include("/tmp/fake_pass_file")
      expect(gpg_call[:args]).not_to include("test-passphrase-from-credentials")
    end

    it "raises BackupError when gpg exits non-zero" do
      allow(Open3).to receive(:capture3) do |*invocation|
        if invocation.first.is_a?(Hash)
          [ "", "", ok_status ]
        else
          [ "", "gpg: error", bad_status ]
        end
      end

      expect { job.perform }.to raise_error(PostgresBackupJob::BackupError, /gpg encryption failed/)
    end
  end

  # ── SFTP upload path ─────────────────────────────────────────────────────

  describe "SFTP upload path" do
    before { job.perform }

    it "uploads to the correct YYYY/MM path" do
      expect(sftp_upload[:remote]).to match(
        %r{expense-tracker/2026/05/expense_tracker_production-20260501T020000Z\.dump\.gpg\z}
      )
    end

    it "creates the remote directory structure before uploading" do
      expect(sftp_session).to have_received(:mkdir!).at_least(3).times
    end

    it "connects to the configured Storage Box host" do
      expect(Net::SFTP).to have_received(:start).with(
        "u000000.your-storagebox.de",
        "u000000",
        hash_including(keys: [ "/run/secrets/storage_box_key" ])
      ).at_least(:once)
    end
  end

  # ── SFTP failure paths ───────────────────────────────────────────────────

  describe "SFTP failure handling" do
    it "re-raises StatusException codes other than FX_FAILURE (e.g. FX_PERMISSION_DENIED)" do
      perm_denied = Net::SFTP::StatusException.new(
        instance_double(Net::SFTP::Response,
          code: Net::SFTP::Constants::StatusCodes::FX_PERMISSION_DENIED,
          message: "permission denied"),
        "permission denied"
      )
      allow(sftp_session).to receive(:mkdir!).and_raise(perm_denied)

      expect { job.perform }.to raise_error(Net::SFTP::StatusException)
    end

    it "ignores FX_FAILURE on mkdir! (directory already exists)" do
      already_exists = Net::SFTP::StatusException.new(
        instance_double(Net::SFTP::Response,
          code: Net::SFTP::Constants::StatusCodes::FX_FAILURE,
          message: "failure"),
        "failure"
      )
      allow(sftp_session).to receive(:mkdir!).and_raise(already_exists)

      expect { job.perform }.not_to raise_error
    end

    it "propagates upload! failures and still cleans up local files" do
      allow(sftp_session).to receive(:upload!).and_raise(StandardError, "connection lost")

      expect { job.perform }.to raise_error(StandardError, /connection lost/)
      expect(FileUtils).to have_received(:rm_f).at_least(2).times
    end

    it "swallows retention failures (backup itself succeeded)" do
      call_count = 0
      allow(Net::SFTP).to receive(:start) do |&block|
        call_count += 1
        if call_count == 1
          block.call(sftp_session) # upload pass succeeds
        else
          raise StandardError, "retention pass exploded"
        end
      end

      expect { job.perform }.not_to raise_error
    end
  end

  # ── retention policy ─────────────────────────────────────────────────────

  describe "#files_to_delete (retention policy)" do
    def filename_for(time)
      "expense_tracker_production-#{time.utc.strftime('%Y%m%dT%H%M%SZ')}.dump.gpg"
    end

    around { |e| travel_to(Time.zone.parse("2026-05-15T02:00:00Z")) { e.run } }

    let(:now) { Time.now.utc }

    let(:daily_files)   { (0..34).map { |n| filename_for(now - n.days) } }
    # 14 prior monthly anchors (n = 1..14, so beginning_of_month -1mo..-14mo)
    let(:monthly_files) { (1..14).map { |n| filename_for(now.beginning_of_month - n.months) } }
    let(:all_files)     { (daily_files + monthly_files).uniq }

    subject(:to_delete) { job.send(:files_to_delete, all_files) }

    it "keeps every file in the 30-day daily window" do
      daily_files.first(30).each do |f|
        expect(to_delete).not_to include(f)
      end
    end

    it "deletes daily backups older than 30 days that are not first-of-month anchors" do
      old_dailies = daily_files[30..].reject do |f|
        m = f.match(/(\d{4})(\d{2})(\d{2})T/)
        m && m[3].to_i == 1
      end
      old_dailies.each do |f|
        expect(to_delete).to include(f)
      end
    end

    # Cutoff = now.beginning_of_month - 11.months = 2025-06-01.
    # Anchors from -1mo (2026-04-01) through -11mo (2025-06-01) are kept (11 files).
    # Anchor at -12mo (2025-05-01) and earlier are deleted.
    it "keeps the 11 most recent prior-month anchors (12 total including current month)" do
      monthly_files.first(11).each do |f|
        expect(to_delete).not_to include(f)
      end
    end

    it "deletes monthly anchors beyond the 12-month window" do
      monthly_files[11..].each do |f|
        expect(to_delete).to include(f)
      end
    end

    it "leaves malformed filenames alone (does not delete them)" do
      garbage = "not-a-backup.dump.gpg"
      result = job.send(:files_to_delete, all_files + [ garbage ])
      expect(result).not_to include(garbage)
    end
  end

  # ── retention end-to-end ─────────────────────────────────────────────────

  describe "retention removes the right files via SFTP" do
    let(:now) { Time.zone.parse("2026-05-15T02:00:00Z") }
    let(:old_filename) do
      # 18 months ago — outside the 30-day daily window AND outside the
      # 12-month monthly window, so the file would be kept as the only
      # anchor for its month otherwise.
      ts = (now - 18.months).utc.strftime("%Y%m%dT%H%M%SZ")
      "expense_tracker_production-#{ts}.dump.gpg"
    end

    around { |e| travel_to(now) { e.run } }

    it "calls remove! for files outside both windows" do
      allow(fake_sftp_dir).to receive(:glob).and_yield(
        instance_double(Net::SFTP::Protocol::V01::Name, name: old_filename)
      )

      job.perform

      expect(sftp_session).to have_received(:remove!).with(
        a_string_including("expense-tracker/")
      )
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

      expect { job.perform }.to raise_error(
        PostgresBackupJob::BackupError, /No GPG passphrase configured/
      )
    end
  end

  # ── observability + cleanup ───────────────────────────────────────────────

  describe "observability" do
    it "writes last_success_at to Rails.cache after a successful backup" do
      job.perform
      expect(Rails.cache).to have_received(:write).with(
        "postgres_backup.last_success_at", anything, hash_including(expires_in: 7.days)
      )
    end
  end

  describe "temp file cleanup" do
    it "removes local dump and encrypted files after uploading" do
      job.perform
      expect(FileUtils).to have_received(:rm_f).at_least(2).times
    end
  end
end
