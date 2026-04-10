class CategorizationMetric < ApplicationRecord
  belongs_to :expense
  belongs_to :category, optional: true
  belongs_to :corrected_to_category, class_name: "Category", optional: true

  validates :layer_used, presence: true,
            inclusion: { in: %w[pattern pg_trgm haiku manual] }

  scope :corrected, -> { where(was_corrected: true) }
  scope :uncorrected, -> { where(was_corrected: false) }
  scope :for_layer, ->(layer) { where(layer_used: layer) }
  scope :recent, ->(period = 30.days) { where(created_at: period.ago..) }
end
