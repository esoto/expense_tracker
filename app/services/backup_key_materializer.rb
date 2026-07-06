# frozen_string_literal: true

# Materializes the Storage Box SSH private key from an environment variable
# into an on-disk keyfile at boot.
#
# PostgresBackupJob uploads via Net::SFTP, which authenticates with a key
# *file* (STORAGE_BOX_SSH_KEY is a path). Kamal, however, can only inject
# secrets as env vars — and its env transport does not survive multiline
# values — so the key travels base64-encoded in STORAGE_BOX_SSH_KEY_CONTENT
# and is written out here (0600) before any job runs.
#
# Wired from config/initializers/backup_ssh_key.rb (PER-527).
module Services
  class BackupKeyMaterializer
    DEFAULT_KEY_PATH = "tmp/storage_box_ed25519"

    # Returns the materialized key path, or nil when there is nothing to do.
    # Never raises: a malformed value logs and leaves ENV untouched so boot
    # continues — PostgresBackupJob then fails loudly with its own BackupError.
    def self.call(env: ENV, root: Rails.root)
      return env["STORAGE_BOX_SSH_KEY"] if env["STORAGE_BOX_SSH_KEY"].present?

      encoded = env["STORAGE_BOX_SSH_KEY_CONTENT"]
      return nil if encoded.blank?

      key = Base64.strict_decode64(encoded.gsub(/\s+/, ""))

      unless key.start_with?("-----BEGIN")
        Rails.logger.error("[BackupKeyMaterializer] decoded STORAGE_BOX_SSH_KEY_CONTENT does not look like a private key (missing -----BEGIN header)")
        return nil
      end

      key = repair_pem_lines(key)
      path = root.join(DEFAULT_KEY_PATH).to_s

      File.write(path, key, perm: 0o600)
      File.chmod(0o600, path) # enforce even when the file already existed
      env["STORAGE_BOX_SSH_KEY"] = path
      path
    rescue ArgumentError => e
      Rails.logger.error("[BackupKeyMaterializer] STORAGE_BOX_SSH_KEY_CONTENT is not valid base64: #{e.message}")
      nil
    end

    # 1Password single-line text fields flatten a pasted key's newlines into
    # spaces, producing a one-line PEM net-ssh cannot parse (prod 2026-07-06).
    # PEM structure is rigid — BEGIN header, base64 body, END footer — so the
    # line breaks can be rebuilt deterministically. Keys that already contain
    # newlines pass through untouched.
    def self.repair_pem_lines(key)
      return key if key.include?("\n")

      match = key.match(/\A(-----BEGIN [A-Z0-9 ]+-----)(.*?)(-----END [A-Z0-9 ]+-----)\s*\z/m)
      return key unless match

      body = match[2].gsub(/\s+/, "")
      "#{match[1]}\n#{body.scan(/.{1,70}/).join("\n")}\n#{match[3]}\n"
    end
    private_class_method :repair_pem_lines
  end
end
