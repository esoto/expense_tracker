class EmailAccount < ApplicationRecord
  # Encryptions
  encrypts :encrypted_password
  encrypts :encrypted_settings

  # Associations
  has_many :expenses, dependent: :destroy
  has_many :parsing_rules, primary_key: :bank_name, foreign_key: :bank_name
  has_many :sync_session_accounts, dependent: :destroy
  has_many :sync_sessions, through: :sync_session_accounts

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :provider, presence: true, inclusion: { in: [ "gmail", "outlook", "yahoo", "custom", "manual" ] }
  validates :bank_name, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_bank, ->(bank) { where(bank_name: bank) }

  # Constants for Costa Rican banks
  COSTA_RICAN_BANKS = [
    "BCR", "Banco de Costa Rica",
    "BAC", "BAC San José",
    "Scotiabank",
    "Banco Nacional", "BNCR",
    "Banco Popular",
    "Davivienda",
    "Coopeservidores",
    "Banco Cathay"
  ].freeze

  # Instance methods
  def display_name
    "#{email} (#{bank_name})"
  end

  def settings
    return {} unless encrypted_settings.present?
    JSON.parse(encrypted_settings)
  rescue JSON::ParserError
    {}
  end

  def settings=(hash)
    self.encrypted_settings = hash.to_json
  end

  def imap_settings
    base_settings = {
      address: imap_server,
      port: imap_port,
      user_name: email,
      password: encrypted_password,
      enable_ssl: true
    }

    base_settings.merge(settings.fetch("imap", {}))
  end

  private

  def imap_server
    case provider
    when "gmail"
      "imap.gmail.com"
    when "outlook"
      "outlook.office365.com"
    when "yahoo"
      "imap.mail.yahoo.com"
    else
      settings.dig("imap", "server") || "localhost"
    end
  end

  def imap_port
    case provider
    when "gmail", "outlook"
      993
    when "yahoo"
      993
    else
      settings.dig("imap", "port") || 993
    end
  end
end
