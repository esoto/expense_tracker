# frozen_string_literal: true

# Authorization rules for Category actions.
#
# Non-admin users can:
#   - view shared categories + their own personal categories
#   - create/edit/destroy their own personal categories
#   - manage patterns on categories they can edit
#
# Admins additionally can edit and destroy shared categories and view any
# user's personal categories (so admin UIs can manage the full tree).
#
# Usage:
#   CategoryPolicy.new(current_user, category).edit?
#   CategoryPolicy.visible_scope(current_user) # => ActiveRecord::Relation
class CategoryPolicy
  attr_reader :user, :category

  def initialize(user, category)
    @user = user
    @category = category
  end

  def show?
    return false if user.nil?
    return true if admin?

    category.shared? || owned_by_user?
  end

  def create?
    return false if user.nil?
    return true if admin?

    # Non-admins cannot create shared categories (user_id nil) and cannot
    # create categories on behalf of another user.
    category.user_id == user.id
  end

  def edit?
    return false if user.nil?
    return true if admin?

    owned_by_user?
  end

  alias update? edit?

  def destroy?
    edit?
  end

  def manage_patterns?
    edit?
  end

  # Returns an ActiveRecord::Relation of categories the user may see.
  # Admins see everything; regular users see shared plus their own personal;
  # a nil user sees nothing — the app requires authentication to hit any
  # category surface, and fail-closed matches `show?(nil, _) == false`.
  def self.visible_scope(user)
    return Category.none if user.nil?
    return Category.all if user.admin?

    Category.visible_to(user)
  end

  private

  def admin?
    user.admin?
  end

  def owned_by_user?
    category.user_id == user.id
  end
end
