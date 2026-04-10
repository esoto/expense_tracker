class CategorizationVector < ApplicationRecord
  belongs_to :category

  validates :merchant_normalized, presence: true
  validates :merchant_normalized, uniqueness: { scope: :category_id }

  scope :for_merchant, ->(merchant) {
    where("similarity(merchant_normalized, ?) > 0.3", merchant)
      .order(Arel.sql("similarity(merchant_normalized, #{connection.quote(merchant)}) DESC"))
      .limit(5)
  }

  scope :stale, ->(threshold = 6.months) { where(last_seen_at: ...threshold.ago) }
end
