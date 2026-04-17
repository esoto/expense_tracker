class LlmCategorizationCacheEntry < ApplicationRecord
  self.table_name = "llm_categorization_cache"

  belongs_to :category

  # PER-499: uniqueness now scoped by prompt_version + model_used so a prompt
  # tweak or model bump doesn't silently serve stale cache. The DB-level
  # index on (merchant_normalized, prompt_version, model_used) is the
  # authoritative guard — this validation is best-effort.
  validates :merchant_normalized, presence: true, uniqueness: { scope: %i[prompt_version model_used] }

  scope :active, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }
  scope :expired, -> { where.not(expires_at: nil).where(expires_at: ...Time.current) }

  # PER-499: single source of truth for the cache composite key. Any future
  # key-field addition (region, locale, ...) happens here — callers in
  # LlmStrategy don't need to change. Prevents the silent cache-poisoning
  # bug where lookup and store drift out of sync.
  def self.cache_key_for(merchant_normalized:)
    {
      merchant_normalized: merchant_normalized,
      prompt_version: Services::Categorization::Llm::PromptBuilder::PROMPT_VERSION,
      model_used: Services::Categorization::Llm::Client::MODEL
    }
  end

  def self.lookup_for(merchant_normalized:)
    find_by(cache_key_for(merchant_normalized: merchant_normalized))
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def refresh_ttl!(ttl = 90.days)
    update!(expires_at: ttl.from_now)
  end
end
