# frozen_string_literal: true

# CanonicalMerchant represents the normalized, canonical version of a merchant name.
# This helps in grouping various representations of the same merchant together
# (e.g., "UBER *TRIP", "UBER TECHNOLOGIES", "Uber" all map to canonical "Uber")
class CanonicalMerchant < ApplicationRecord
  # Associations
  has_many :merchant_aliases, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :usage_count, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :popular, -> { where("usage_count >= ?", 10) }
  scope :with_category_hint, -> { where.not(category_hint: [ nil, "" ]) }
  scope :alphabetical, -> { order(:name) }
  scope :by_usage, -> { order(usage_count: :desc) }

  # Callbacks
  before_save :normalize_name

  # Class Methods

  # Find or create a canonical merchant from a raw merchant name
  def self.find_or_create_from_raw(raw_name)
    return nil if raw_name.blank?

    normalized = normalize_merchant_name(raw_name)

    # First check if we have an alias for this exact raw name
    alias_record = MerchantAlias.find_by(raw_name: raw_name)
    return alias_record.canonical_merchant if alias_record

    # Check if we have an alias for the normalized name
    alias_record = MerchantAlias.find_by(normalized_name: normalized)
    return alias_record.canonical_merchant if alias_record

    # Try fuzzy matching for similar canonical merchants
    canonical = find_similar_canonical(normalized)

    if canonical
      # Create an alias for this raw name
      MerchantAlias.create!(
        raw_name: raw_name,
        normalized_name: normalized,
        canonical_merchant: canonical,
        confidence: calculate_similarity_confidence(normalized, canonical.name)
      )
      canonical
    else
      # Create new canonical merchant
      canonical = create!(
        name: normalized,
        display_name: beautify_merchant_name(normalized)
      )

      # Create alias for the raw name
      MerchantAlias.create!(
        raw_name: raw_name,
        normalized_name: normalized,
        canonical_merchant: canonical,
        confidence: 1.0
      )

      canonical
    end
  end

  # Normalize a merchant name
  def self.normalize_merchant_name(name)
    return "" if name.blank?

    normalized = name.dup

    # Remove common payment processor prefixes/suffixes
    normalized.gsub!(/^(PAYPAL\s*\*|SQ\s*\*|SQUARE\s*\*|TST\*|POS\s+|CCD\s+)/i, "")
    normalized.gsub!(/\s*\*\s*/, " ")

    # Remove transaction IDs and numbers at the end
    normalized.gsub!(/\s+\d{4,}$/, "")
    normalized.gsub!(/\s+#\d+$/, "")

    # Remove common suffixes
    normalized.gsub!(/\s+(INC|LLC|LTD|CORP|CO|COMPANY)\.?$/i, "")

    # Remove location indicators
    normalized.gsub!(/\s+(STORE|LOCATION)\s*#?\d+/i, "")

    # Clean up whitespace and special characters
    normalized.gsub!(/[^\w\s&'-]/, " ")
    normalized.squeeze!(" ")
    normalized.strip!
    normalized.downcase!

    normalized
  end

  # Beautify a merchant name for display
  def self.beautify_merchant_name(name)
    return "" if name.blank?

    # Special cases for known merchants
    known_merchants = {
      "uber" => "Uber",
      "lyft" => "Lyft",
      "amazon" => "Amazon",
      "walmart" => "Walmart",
      "target" => "Target",
      "starbucks" => "Starbucks",
      "mcdonalds" => "McDonald's",
      "netflix" => "Netflix",
      "spotify" => "Spotify"
    }

    normalized = name.downcase.strip
    return known_merchants[normalized] if known_merchants[normalized]

    # Title case for unknown merchants
    name.split(/\s+/).map(&:capitalize).join(" ")
  end

  # Find similar canonical merchant using fuzzy matching
  def self.find_similar_canonical(normalized_name)
    return nil if normalized_name.blank?

    if ActiveRecord::Base.connection.extension_enabled?("pg_trgm")
      # Use trigram similarity for fuzzy matching
      result = connection.execute(
        sanitize_sql_array([
          "SELECT id, name, similarity(name, ?) AS sim
           FROM canonical_merchants
           WHERE similarity(name, ?) > 0.6
           ORDER BY sim DESC
           LIMIT 1",
          normalized_name, normalized_name
        ])
      ).first

      result ? find(result["id"]) : nil
    else
      # Fallback to exact match
      find_by("LOWER(name) = ?", normalized_name.downcase)
    end
  end

  # Calculate similarity confidence between two strings
  def self.calculate_similarity_confidence(str1, str2)
    return 0.0 if str1.blank? || str2.blank?

    if ActiveRecord::Base.connection.extension_enabled?("pg_trgm")
      result = connection.execute(
        sanitize_sql_array([
          "SELECT similarity(?, ?) AS sim",
          str1.downcase, str2.downcase
        ])
      ).first

      result ? result["sim"].to_f : 0.0
    else
      # Simple character-based similarity
      str1_chars = str1.downcase.chars.sort
      str2_chars = str2.downcase.chars.sort
      common = (str1_chars & str2_chars).size
      total = [ str1_chars.size, str2_chars.size ].max

      total.positive? ? common.to_f / total : 0.0
    end
  end

  # Instance Methods

  # Record usage of this canonical merchant
  def record_usage
    increment!(:usage_count)
    touch(:updated_at)
  end

  # Get all raw merchant names associated with this canonical merchant
  def all_raw_names
    merchant_aliases.pluck(:raw_name).uniq
  end

  # Get the most common raw name
  def most_common_raw_name
    merchant_aliases
      .group(:raw_name)
      .order("COUNT(*) DESC")
      .limit(1)
      .pluck(:raw_name)
      .first || name
  end

  # Merge another canonical merchant into this one
  def merge_with(other_canonical)
    return if other_canonical == self

    transaction do
      # Move all aliases
      other_canonical.merchant_aliases.update_all(canonical_merchant_id: id)

      # Update usage count
      self.usage_count += other_canonical.usage_count

      # Merge metadata
      self.metadata = metadata.merge(other_canonical.metadata) if other_canonical.metadata.present?

      # Keep the better display name
      if display_name.blank? && other_canonical.display_name.present?
        self.display_name = other_canonical.display_name
      end

      # Keep category hint if we don't have one
      if category_hint.blank? && other_canonical.category_hint.present?
        self.category_hint = other_canonical.category_hint
      end

      save!

      # Delete the other canonical merchant
      other_canonical.destroy!
    end
  end

  # Suggest a category based on the merchant
  def suggest_category
    return nil if category_hint.blank?

    Category.find_by(name: category_hint)
  end

  private

  def normalize_name
    self.name = self.class.normalize_merchant_name(name) if name_changed?
  end
end
