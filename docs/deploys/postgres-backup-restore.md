# Postgres Backup & Restore Runbook (PER-527)

The `PostgresBackupJob` runs nightly at **02:00 UTC** via Solid Queue
(`config/recurring.yml`). It dumps `expense_tracker_production` with
`pg_dump --format=custom`, GPG-encrypts the dump (AES256, symmetric), uploads
it to the Hetzner Storage Box via SFTP, and applies retention.

## RTO / RPO targets

- **RPO** (data loss tolerance): up to 24h. The backup runs once nightly.
  An incident at 23:59 UTC would lose ~24h of expenses/categorizations.
- **RTO** (recovery time): ~30 min for the data restore itself, plus
  whatever time is needed to redeploy the app on a fresh host.

## Retention

- **Daily**: every backup whose timestamp is within the last 30 days
- **Monthly**: the first-of-month anchor for 12 months total (current month
  + 11 prior)
- Anything else is deleted by `apply_retention` immediately after each
  successful upload.

## Required secrets (production)

Set in 1Password vault `Personal Brand → Expense Tracker` and synced via
`.kamal/secrets`:

- `STORAGE_BOX_HOST` — e.g. `u123456.your-storagebox.de`
- `STORAGE_BOX_USER` — Storage Box SSH username
- `STORAGE_BOX_SSH_KEY` — path to private key inside the container
  (e.g. `/run/secrets/storage_box_key`)
- `BACKUP_GPG_PASSPHRASE` — symmetric encryption passphrase (≥32 chars)

`bin/pre-deploy-check` enforces all four are present before deploy.

## Operator commands

```bash
bin/rails postgres_backup:run_now        # kick off a backup immediately
bin/rails postgres_backup:list_remote    # list what's in the Storage Box
bin/rails 'postgres_backup:restore[FILENAME]'   # download + decrypt
```

The `restore` task validates the filename against the strict pattern
`expense_tracker_production-YYYYMMDDTHHMMSSZ.dump.gpg` and writes the
decrypted dump to a private tmpdir (override with `OUTPUT_DIR=`).

## Restore procedure (full DR)

1. **Pick a backup**: `bin/rails postgres_backup:list_remote` — copy the
   most recent (or most recent monthly anchor for point-in-time recovery).
2. **Download + decrypt** on the new host:
   ```bash
   bin/rails 'postgres_backup:restore[expense_tracker_production-YYYYMMDDTHHMMSSZ.dump.gpg]'
   ```
   The task prints the path to the decrypted `.dump` file.
3. **Restore into a fresh database**:
   ```bash
   createdb expense_tracker_restore_test
   pg_restore --clean --if-exists --no-owner --no-acl \
     -d expense_tracker_restore_test \
     /path/to/decrypted.dump
   ```
4. **Verify** the restore (row counts, latest expense ID, latest sync_session)
   before pointing app config at it.
5. **Switch over** by updating `DATABASE_URL` (or the production credentials)
   and running `kamal deploy`.
6. **Clean up**: `rm` the decrypted dump file. It contains plaintext bank PII.

## Quarterly drill checklist

Run on the first weekend of each quarter and record completion in this file
(or your ops journal). Untested backups are not backups.

- [ ] `bin/rails postgres_backup:list_remote` — confirm last backup is
      ≤ 24h old and that you see ~30 daily files plus 12 monthly anchors.
- [ ] Pick a backup ≥ 7 days old (not just last night's).
- [ ] Decrypt it via `postgres_backup:restore[FILENAME]` on a non-production
      host (laptop or scratch VPS).
- [ ] `pg_restore` it into a fresh local database.
- [ ] Spot-check: `SELECT COUNT(*) FROM expenses;`, `SELECT MAX(created_at)
      FROM expenses;`, plus one ML-categorized row to confirm encrypted
      columns decrypt correctly with the production credentials.
- [ ] `rm` the decrypted dump.

## Failure-mode runbook

| Symptom | First check | Likely fix |
| --- | --- | --- |
| `list_remote` empty for >24h | Solid Queue dispatcher up? `kamal app logs --grep PostgresBackup` | Restart Puma; investigate why the recurring task didn't fire |
| `BackupError: pg_dump failed` | Postgres host reachable from app container? Disk full on the DB host? | Operational — check `personal-blog-db` |
| `BackupError: gpg encryption failed` | Disk space in `/tmp` of app container | `df -h` inside container; free up `/tmp` |
| `Net::SSH::AuthenticationFailed` | SSH key path correct? `STORAGE_BOX_SSH_KEY` points at a valid file inside the container? | Re-mount key via `.kamal/secrets`; verify perms 0600 |
| Retention pass logs failure | Storage Box quota exhausted? | Free space manually via SFTP, then re-run `postgres_backup:run_now` |
| Backup completed but no `last_success_at` cache entry | Solid Cache writable? | Inspect `Rails.cache.read("postgres_backup.last_success_at")`; check `cache:` DB |

## Observability

After each successful run, `Rails.cache.write("postgres_backup.last_success_at", iso8601, expires_in: 7.days)`.
A future PR can wire this into the admin dashboard or `/up` healthcheck so a
multi-day backup gap surfaces without log diving.

## Related work

- **PER-527** (this PR) — initial implementation
- **PER-523** — recurring-job heartbeat + alert on liveness gap (broader
  monitoring; will replace the cache-write approach above)
- **PER-528** — pre-prod load test (will exercise dump size against
  retention assumptions)
