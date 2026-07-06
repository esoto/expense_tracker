# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::BackupKeyMaterializer, :unit do
  let(:key_material) { "-----BEGIN OPENSSH PRIVATE KEY-----\nabc123\n-----END OPENSSH PRIVATE KEY-----\n" }
  let(:encoded) { Base64.strict_encode64(key_material) }
  let(:root) { Pathname.new(Dir.mktmpdir) }

  before { FileUtils.mkdir_p(root.join("tmp")) }
  after { FileUtils.remove_entry(root) }

  def call(env)
    described_class.call(env: env, root: root)
  end

  it "writes the decoded key to tmp with 0600 permissions and sets STORAGE_BOX_SSH_KEY" do
    env = { "STORAGE_BOX_SSH_KEY_CONTENT" => encoded }

    path = call(env)

    expect(path).to eq(root.join(described_class::DEFAULT_KEY_PATH).to_s)
    expect(File.read(path)).to eq(key_material)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(env["STORAGE_BOX_SSH_KEY"]).to eq(path)
  end

  describe "PEM line repair (1Password single-line fields flatten newlines to spaces)" do
    it "rebuilds a flattened one-line key into valid PEM structure" do
      flattened = "-----BEGIN OPENSSH PRIVATE KEY----- abc123 -----END OPENSSH PRIVATE KEY-----"
      env = { "STORAGE_BOX_SSH_KEY_CONTENT" => Base64.strict_encode64(flattened) }

      path = call(env)

      expect(File.read(path)).to eq(key_material)
    end

    it "re-wraps a long flattened body at 70 columns" do
      body = "A" * 140
      flattened = "-----BEGIN OPENSSH PRIVATE KEY----- #{body[0, 70]} #{body[70, 70]} -----END OPENSSH PRIVATE KEY-----"
      env = { "STORAGE_BOX_SSH_KEY_CONTENT" => Base64.strict_encode64(flattened) }

      path = call(env)

      expect(File.read(path)).to eq(
        "-----BEGIN OPENSSH PRIVATE KEY-----\n#{body[0, 70]}\n#{body[70, 70]}\n-----END OPENSSH PRIVATE KEY-----\n"
      )
    end

    it "repairs a flattened key that kept only its trailing newline" do
      flattened = "-----BEGIN OPENSSH PRIVATE KEY----- abc123 -----END OPENSSH PRIVATE KEY-----\n"
      env = { "STORAGE_BOX_SSH_KEY_CONTENT" => Base64.strict_encode64(flattened) }

      path = call(env)

      expect(File.read(path)).to eq(key_material)
    end

    it "leaves a properly multiline key byte-identical" do
      env = { "STORAGE_BOX_SSH_KEY_CONTENT" => encoded }

      path = call(env)

      expect(File.read(path)).to eq(key_material)
    end
  end

  it "tolerates whitespace and newlines inside the base64 payload" do
    wrapped = encoded.scan(/.{1,40}/).join("\n")
    env = { "STORAGE_BOX_SSH_KEY_CONTENT" => wrapped }

    path = call(env)

    expect(File.read(path)).to eq(key_material)
  end

  it "returns the existing path untouched when STORAGE_BOX_SSH_KEY is already set" do
    env = { "STORAGE_BOX_SSH_KEY" => "/run/secrets/key", "STORAGE_BOX_SSH_KEY_CONTENT" => encoded }

    expect(call(env)).to eq("/run/secrets/key")
    expect(File.exist?(root.join(described_class::DEFAULT_KEY_PATH))).to be(false)
  end

  it "no-ops when no key content is present" do
    env = {}

    expect(call(env)).to be_nil
    expect(env).not_to have_key("STORAGE_BOX_SSH_KEY")
    expect(File.exist?(root.join(described_class::DEFAULT_KEY_PATH))).to be(false)
  end

  it "logs and leaves ENV untouched when the decoded payload is not a private key" do
    env = { "STORAGE_BOX_SSH_KEY_CONTENT" => Base64.strict_encode64("garbage from a failed op read") }
    allow(Rails.logger).to receive(:error)

    expect(call(env)).to be_nil
    expect(env).not_to have_key("STORAGE_BOX_SSH_KEY")
    expect(File.exist?(root.join(described_class::DEFAULT_KEY_PATH))).to be(false)
    expect(Rails.logger).to have_received(:error).with(/does not look like a private key/)
  end

  it "logs and leaves ENV untouched when the payload is not valid base64" do
    env = { "STORAGE_BOX_SSH_KEY_CONTENT" => "not-base64!!!" }
    allow(Rails.logger).to receive(:error)

    expect(call(env)).to be_nil
    expect(env).not_to have_key("STORAGE_BOX_SSH_KEY")
    expect(Rails.logger).to have_received(:error).with(/not valid base64/)
  end

  it "overwrites a stale keyfile and re-enforces 0600" do
    stale_path = root.join(described_class::DEFAULT_KEY_PATH)
    File.write(stale_path, "old key")
    File.chmod(0o644, stale_path)
    env = { "STORAGE_BOX_SSH_KEY_CONTENT" => encoded }

    call(env)

    expect(File.read(stale_path)).to eq(key_material)
    expect(File.stat(stale_path).mode & 0o777).to eq(0o600)
  end
end
