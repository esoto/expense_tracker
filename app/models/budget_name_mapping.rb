# frozen_string_literal: true

# Name-keyed cache of budget-name → category mappings, and the memory of
# user confirmations. One row per (user, normalized budget name). The
# suggester (Services::Budgets::MappingSuggester) writes exact/fuzzy/llm
# rows; the future review UI upgrades rows to source: :user.
class BudgetNameMapping < ApplicationRecord
  belongs_to :user
  belongs_to :category, optional: true

  enum :kind, { category: 0, allocation: 1 }, prefix: :kind
  enum :source, { exact: 0, fuzzy: 1, llm: 2, user: 3 }, prefix: :source

  validates :normalized_name, presence: true, uniqueness: { scope: :user_id }
  validates :category, presence: true, if: :kind_category?

  scope :for_lookup, ->(user, normalized) { where(user: user, normalized_name: normalized) }

  # Single normalization entry point — every reader/writer of
  # normalized_name MUST go through this or cache lookups silently miss.
  def self.normalize(text)
    text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.squish
  end

  # Only exact matches and user confirmations may be applied without review.
  def auto_applicable?
    source_user? || source_exact?
  end
end
