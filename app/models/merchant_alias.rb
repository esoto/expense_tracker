# frozen_string_literal: true

# MerchantAlias maps raw merchant names from bank transactions to their
# canonical merchant representations. This helps handle variations in how
# the same merchant appears in different transactions.
class MerchantAlias < ApplicationRecord
  # Constants
  MIN_CONFIDENCE = 0.0
  MAX_CONFIDENCE = 1.0
  HIGH_CONFIDENCE_THRESHOLD = 0.8

  # Associations
  belongs_to :canonical_merchant

  # Validations
  validates :raw_name, presence: true
  validates :normalized_name, presence: true
  validates :confidence,
            numericality: {
              greater_than_or_equal_to: MIN_CONFIDENCE,
              less_than_or_equal_to: MAX_CONFIDENCE
            }
  validates :match_count, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :high_confidence, -> { where("confidence >= ?", HIGH_CONFIDENCE_THRESHOLD) }
  scope :low_confidence, -> { where("confidence < ?", HIGH_CONFIDENCE_THRESHOLD) }
  scope :recent, -> { order(last_seen_at: :desc) }
  scope :frequently_matched, -> { where("match_count >= ?", 5) }
  scope :for_merchant, ->(merchant) { where(canonical_merchant: merchant) }

  # Callbacks
  before_validation :set_normalized_name
  after_create :update_canonical_usage

  # Class Methods

  # Find the best matching alias for a raw merchant name
  def self.find_best_match(raw_name)
    return nil if raw_name.blank?

    # First try exact match
    exact_match = find_by(raw_name: raw_name)
    return exact_match if exact_match

    # Try normalized match
    normalized = CanonicalMerchant.normalize_merchant_name(raw_name)
    normalized_match = find_by(normalized_name: normalized)
    return normalized_match if normalized_match

    # Try fuzzy matching if trigram extension is available
    fuzzy_match(raw_name)
  end

  # Fuzzy match using trigram similarity
  def self.fuzzy_match(name)
    return nil if name.blank?

    if ActiveRecord::Base.connection.extension_enabled?("pg_trgm")
      normalized = CanonicalMerchant.normalize_merchant_name(name)

      result = connection.execute(
        sanitize_sql_array([
          "SELECT id, normalized_name, confidence,
                  similarity(normalized_name, ?) AS sim
           FROM merchant_aliases
           WHERE similarity(normalized_name, ?) > 0.5
           ORDER BY sim DESC, confidence DESC
           LIMIT 1",
          normalized, normalized
        ])
      ).first

      result ? find(result["id"]) : nil
    else
      nil
    end
  end

  # Create or update an alias
  def self.record_alias(raw_name, canonical_merchant, confidence: 0.8)
    return nil if raw_name.blank? || canonical_merchant.nil?

    normalized = CanonicalMerchant.normalize_merchant_name(raw_name)

    alias_record = find_or_initialize_by(
      raw_name: raw_name,
      canonical_merchant: canonical_merchant
    )

    if alias_record.new_record?
      alias_record.normalized_name = normalized
      alias_record.confidence = confidence
      alias_record.match_count = 1
      alias_record.last_seen_at = Time.current
      alias_record.save!
    else
      alias_record.record_match
    end

    alias_record
  end

  # Instance Methods

  # Record that this alias was matched
  def record_match
    self.match_count += 1
    self.last_seen_at = Time.current

    # Increase confidence based on successful matches
    if match_count > 10 && confidence < 0.95
      self.confidence = [ confidence * 1.05, 0.95 ].min
    end

    save!
  end

  # Check if this is a high-confidence alias
  def high_confidence?
    confidence >= HIGH_CONFIDENCE_THRESHOLD
  end

  # Get similarity to another name
  def similarity_to(other_name)
    return 0.0 if other_name.blank?

    CanonicalMerchant.calculate_similarity_confidence(normalized_name, other_name)
  end

  # Should this alias be trusted for automatic categorization?
  def trustworthy?
    high_confidence? && match_count >= 3
  end

  # Merge with another alias for the same canonical merchant
  def merge_with(other_alias)
    return if other_alias == self
    return unless other_alias.canonical_merchant_id == canonical_merchant_id

    transaction do
      # Combine match counts
      self.match_count += other_alias.match_count

      # Take the higher confidence
      self.confidence = [ confidence, other_alias.confidence ].max

      # Update last seen to the more recent
      if other_alias.last_seen_at && (!last_seen_at || other_alias.last_seen_at > last_seen_at)
        self.last_seen_at = other_alias.last_seen_at
      end

      save!

      # Remove the other alias
      other_alias.destroy!
    end
  end

  private

  def set_normalized_name
    if raw_name.present? && normalized_name.blank?
      self.normalized_name = CanonicalMerchant.normalize_merchant_name(raw_name)
    end
  end

  def update_canonical_usage
    canonical_merchant.record_usage if canonical_merchant
  end
end
