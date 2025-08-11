class Category < ApplicationRecord
  # Associations
  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: "parent_id", dependent: :nullify
  has_many :expenses, dependent: :nullify
  has_many :categorization_patterns, dependent: :destroy
  has_many :composite_patterns, dependent: :destroy
  has_many :pattern_feedbacks, dependent: :destroy
  has_many :pattern_learning_events, dependent: :destroy
  has_many :user_category_preferences, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, message: "must be a valid hex color" }, allow_blank: true
  validate :cannot_be_parent_of_itself

  # Scopes
  scope :root_categories, -> { where(parent_id: nil) }
  scope :subcategories, -> { where.not(parent_id: nil) }

  # Instance methods
  def root?
    parent_id.nil?
  end

  def subcategory?
    !root?
  end

  def full_name
    return name if root?
    "#{parent.name} > #{name}"
  end

  # Check if this is a user-specific category (placeholder for future implementation)
  def user_specific?
    false # Will be implemented when user-specific categories are added
  end

  private

  def cannot_be_parent_of_itself
    return unless parent_id.present? && id.present?

    if id == parent_id
      errors.add(:parent, "cannot be itself")
    elsif parent&.parent_id == id
      errors.add(:parent, "cannot create circular reference")
    end
  end
end
