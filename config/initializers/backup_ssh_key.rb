# frozen_string_literal: true

# Writes the Storage Box SSH private key from STORAGE_BOX_SSH_KEY_CONTENT
# (base64, injected by Kamal from 1Password) to an on-disk 0600 keyfile and
# points STORAGE_BOX_SSH_KEY at it, so PostgresBackupJob's Net::SFTP client
# can authenticate. No-ops when the env is absent (dev, test, CI). PER-527.
Rails.application.config.after_initialize do
  Services::BackupKeyMaterializer.call
end
