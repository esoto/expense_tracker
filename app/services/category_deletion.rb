# frozen_string_literal: true

module Services
  # Removes a category along with its downstream state using one of two
  # strategies. Lives in a service object because the steps — moving or
  # nullifying expenses, budgets, children, patterns — must run atomically,
  # and the controller shouldn't care about the plumbing.
  #
  # Usage:
  #
  #   result = Services::CategoryDeletion.new(
  #     category: category,
  #     actor: current_user,
  #     strategy: :reassign,  # or :orphan
  #     reassign_to: target_category
  #   ).call
  #
  #   if result.success
  #     redirect_to categories_path, notice: "Category deleted."
  #   else
  #     flash[:alert] = result.error
  #   end
  #
  # Rules enforced here (intentionally not in the controller):
  #
  # - Actor authorization: mirrors CategoryPolicy#destroy?.
  # - Orphan strategy: forbidden for shared categories. Admins deleting a
  #   shared category must reassign — anything else would cross-wire
  #   downstream state for every user who sees that shared category.
  # - Reassign target: must be visible to the actor; cannot be the
  #   category being deleted.
  # - Personal children under a shared parent block the shared parent's
  #   deletion entirely. The admin must ask those users to reparent or
  #   delete their children first. This is a safety net, not a user-facing
  #   flow — the UI would normally prevent reaching this state.
  #
  # Transactional: any raise inside ActiveRecord::Base.transaction rolls
  # everything back, so a unique-index violation on budget reassignment
  # (e.g. the target already has an active budget for the same period)
  # leaves the source intact.
  class CategoryDeletion
    Result = Struct.new(:success, :error, keyword_init: true)

    VALID_STRATEGIES = %i[reassign orphan].freeze

    def initialize(category:, actor:, strategy:, reassign_to: nil)
      @category    = category
      @actor       = actor
      @strategy    = strategy
      @reassign_to = reassign_to
    end

    def call
      validation_error = validate
      return failure(validation_error) if validation_error

      ActiveRecord::Base.transaction do
        case @strategy
        when :reassign then reassign_dependents!
        when :orphan   then orphan_dependents!
        end
        @category.destroy!
      end

      success
    rescue ActiveRecord::RecordInvalid,
           ActiveRecord::RecordNotDestroyed,
           ActiveRecord::RecordNotUnique => e
      failure(e.message)
    end

    private

    def validate
      return "You do not have permission to delete this category." unless authorized?
      return "Strategy must be :reassign or :orphan." unless VALID_STRATEGIES.include?(@strategy)
      return "Shared categories must use :reassign." if @category.shared? && @strategy == :orphan
      return blocked_by_personal_children_reason if blocked_by_personal_children?

      if @strategy == :reassign
        return "A reassign target is required."            if @reassign_to.nil?
        return "Cannot reassign to the deleted category."  if @reassign_to.id == @category.id
        return "Reassign target is not accessible."        unless reassign_target_visible?
        return "Reassign target cannot be a descendant."   if reassign_target_is_descendant?
      end

      nil
    end

    def authorized?
      CategoryPolicy.new(@actor, @category).destroy?
    end

    def reassign_target_visible?
      CategoryPolicy.new(@actor, @reassign_to).show?
    end

    # Walk up the parent chain from the reassign target: if we encounter
    # the category being deleted, the target is a descendant. Reparenting
    # children to a descendant would create a cycle (or reparent the target
    # to itself once its parent is destroyed). `update_all` bypasses the
    # model's `cannot_be_parent_of_itself` validation, so this check is the
    # last line of defense against corruption of the tree.
    def reassign_target_is_descendant?
      current = @reassign_to
      seen = Set.new
      while current && !seen.include?(current.id)
        return true if current.id == @category.id
        seen << current.id
        current = current.parent
      end
      false
    end

    # Deleting a shared category while some user has a personal child under
    # it would orphan those children unexpectedly. Block instead.
    def blocked_by_personal_children?
      @category.shared? && @category.children.where.not(user_id: nil).exists?
    end

    def blocked_by_personal_children_reason
      "Cannot delete: this shared category has personal children belonging to other users. Reparent them first."
    end

    def reassign_dependents!
      @category.expenses.update_all(category_id: @reassign_to.id)
      @category.children.update_all(parent_id: @reassign_to.id)
      Budget.where(category_id: @category.id).update_all(category_id: @reassign_to.id)
      # Patterns belong to the source category's identity. Destroy them
      # explicitly so we do not move them and confuse the matcher.
      @category.categorization_patterns.destroy_all
    end

    def orphan_dependents!
      # `dependent: :nullify` on expenses + children does the right thing
      # when we destroy the category below, but we explicitly nullify
      # here so the intent is visible at the service level and so budgets
      # (which lack a Rails-level cascade) get nulled too.
      @category.expenses.update_all(category_id: nil)
      @category.children.update_all(parent_id: nil)
      Budget.where(category_id: @category.id).update_all(category_id: nil)
      @category.categorization_patterns.destroy_all
    end

    def success
      Result.new(success: true, error: nil)
    end

    def failure(message)
      Result.new(success: false, error: message)
    end
  end
end
