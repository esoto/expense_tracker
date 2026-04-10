class LlmCategorizationCacheEntry < ApplicationRecord
  self.table_name = "llm_categorization_cache"

  belongs_to :category

  validates :merchant_normalized, presence: true, uniqueness: true

  scope :active, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def refresh_ttl!(ttl = 90.days)
    update!(expires_at: ttl.from_now)
  end
end
