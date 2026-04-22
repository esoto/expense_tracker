class Category < ApplicationRecord
  # Associations
  belongs_to :parent, class_name: "Category", optional: true
  belongs_to :user, optional: true
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
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }, if: :personal?
  validate :cannot_be_parent_of_itself
  validate :parent_ownership_must_match
  validate :user_id_change_preserves_children

  # Scopes
  scope :root_categories, -> { where(parent_id: nil) }
  scope :subcategories, -> { where.not(parent_id: nil) }
  scope :active, -> { all } # For now, all categories are considered active
  scope :shared, -> { where(user_id: nil) }
  scope :personal_for, ->(user) { where(user_id: user.id) }
  scope :visible_to, ->(user) { where(user_id: [ nil, user.id ]) }

  # Instance methods
  def root?
    parent_id.nil?
  end

  def subcategory?
    !root?
  end

  def shared?
    user_id.nil?
  end

  def personal?
    !shared?
  end

  def display_name
    return name unless i18n_key.present?

    I18n.t("categories.names.#{i18n_key}", default: name)
  end

  def full_name
    return display_name if root?
    "#{parent.display_name} > #{display_name}"
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

  # Ownership rules between a category and its parent:
  #
  #   parent          | self            | allowed?
  #   ----------------+-----------------+-----------------------------
  #   shared          | shared          | yes
  #   shared          | personal (A)    | yes  (personal subcategory under shared)
  #   personal (A)    | personal (A)    | yes  (personal child under own branch)
  #   personal (A)    | personal (B)    | NO   (cross-user leakage)
  #   personal (A)    | shared          | NO   (shared must not depend on personal)
  #
  def parent_ownership_must_match
    return unless parent

    if parent.personal? && shared?
      errors.add(:parent, "shared category cannot have a personal parent")
    elsif parent.personal? && user_id != parent.user_id
      errors.add(:parent, "must belong to the same user or be shared")
    end
  end

  # Changing a category's `user_id` can silently invalidate its existing
  # children's `parent_ownership_must_match` state (e.g. a shared parent
  # with shared children becomes personal, making the children invalid).
  # Forbid the change while children exist — re-ownership is unusual and
  # the safe workflow is to move or reparent children first.
  def user_id_change_preserves_children
    return unless persisted? && user_id_changed? && children.exists?

    errors.add(:user_id, "cannot change while the category has children")
  end
end
