class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]
  before_action :authorize_show!, only: %i[show]
  before_action :authorize_edit!, only: %i[edit update destroy]
  before_action :scope_parent_id, only: %i[create update]

  # Associations that block an "empty category" fast-path destroy in this PR.
  # Anything touching a category's identity must be resolved by PR 8's
  # CategoryDeletion service (reassign vs. orphan). This list mirrors the
  # dependent: :destroy/:nullify associations on Category.
  DELETE_BLOCKING_ASSOCIATIONS = %i[
    expenses
    children
    categorization_patterns
    composite_patterns
    pattern_feedbacks
    pattern_learning_events
    user_category_preferences
  ].freeze

  # GET /categories(.json)
  #
  # HTML: renders a two-column tree view — shared categories (with the
  # user's personal subcategories nested under their shared parents) on
  # the left, personal top-level branches on the right. Single query;
  # children are grouped in memory to avoid N+1.
  #
  # JSON: flat list kept for existing dropdown consumers.
  def index
    @categories = CategoryPolicy.visible_scope(current_user).order(:name)

    respond_to do |format|
      format.html do
        build_category_tree(@categories)
      end
      format.json do
        render json: @categories.map { |category|
          {
            id: category.id,
            name: category.display_name,
            color: category.color,
            parent_id: category.parent_id
          }
        }
      end
    end
  end

  # GET /categories/:id
  def show
  end

  # GET /categories/new
  #
  # Supports ?parent_id=X to prefill the parent selector, used by the
  # inline "+ Add subcategory" affordance on each shared root in the tree
  # view. The parent_id is validated against the visible scope — an
  # invalid or out-of-scope id is silently dropped (the user can still
  # pick a parent from the form).
  def new
    parent = resolve_prefill_parent(params[:parent_id])
    @category = Category.new(user: current_user, parent: parent)
  end

  # POST /categories
  def create
    @category = Category.new(category_params.merge(user: current_user))

    if CategoryPolicy.new(current_user, @category).create? && @category.save
      redirect_to category_path(@category), notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /categories/:id/edit
  def edit
  end

  # PATCH/PUT /categories/:id
  def update
    if @category.update(category_params)
      redirect_to category_path(@category), notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /categories/:id
  #
  # PR 3 ships a narrow destroy that only deletes *empty* personal categories
  # — no expenses, no children, no patterns, no feedbacks/metrics/preferences.
  # The full reassign/orphan flow is the subject of PR 8 (CategoryDeletion
  # service); refusing a non-empty destroy here avoids silent cascade of
  # dependent: :destroy associations.
  def destroy
    if category_in_use?
      redirect_to category_path(@category),
                  alert: "This category is in use. Full deletion flow arrives in PR 8.",
                  status: :see_other
    else
      @category.destroy
      redirect_to categories_path, notice: "Category deleted.", status: :see_other
    end
  end

  private

  def set_category
    # Hide existence of other users' personal categories by returning 404
    # instead of 403. Admins see everything.
    @category = CategoryPolicy.visible_scope(current_user).find_by(id: params[:id])
    render_not_found if @category.nil?
  end

  def authorize_show!
    render_not_found unless CategoryPolicy.new(current_user, @category).show?
  end

  def authorize_edit!
    return if CategoryPolicy.new(current_user, @category).edit?

    if @category.user_id == current_user.id
      render_not_found # shouldn't hit this branch; defensive
    elsif @category.shared?
      # Non-admin trying to edit a shared category: redirect, don't 404.
      redirect_to category_path(@category), alert: "Shared categories are read-only.", status: :see_other
    else
      render_not_found
    end
  end

  def category_params
    # user_id is intentionally NOT permitted. Ownership is forced to
    # current_user at create time and immutable thereafter (see Category
    # model's user_id_change_preserves_children validation).
    # i18n_key is not user-facing yet (used for shared category translation
    # keys) — omit from permitted params until the admin UI lands.
    params.require(:category).permit(:name, :description, :color, :parent_id)
  end

  # Reject parent_id values that point at categories the current user cannot
  # see (other users' personal categories or nonexistent IDs) before they
  # reach the model. Without this, the model validation fires and returns
  # 422 — which leaks the existence of hidden categories via error message
  # differences. Normalize to 404 (out-of-scope) instead.
  def scope_parent_id
    pid = params.dig(:category, :parent_id)
    return if pid.blank?

    unless CategoryPolicy.visible_scope(current_user).exists?(id: pid)
      render_not_found
    end
  end

  def category_in_use?
    DELETE_BLOCKING_ASSOCIATIONS.any? { |assoc| @category.public_send(assoc).exists? }
  end

  # Splits the visible category set into shared roots, personal roots, and a
  # parent_id → [children] lookup so the tree view can render recursively
  # without per-node queries. current_user_id can be nil (unauthenticated
  # contexts shouldn't reach here because of require_authentication, but the
  # nil-safe split keeps the view robust).
  def build_category_tree(categories)
    grouped = categories.group_by { |c| tree_bucket_for(c) }
    @shared_roots      = grouped.fetch(:shared_root, [])
    @personal_roots    = grouped.fetch(:personal_root, [])
    @children_by_parent = categories.group_by(&:parent_id)
  end

  def tree_bucket_for(category)
    return :shared_root   if category.parent_id.nil? && category.shared?
    return :personal_root if category.parent_id.nil? && category.personal?

    :child
  end

  def resolve_prefill_parent(id)
    return nil if id.blank?

    CategoryPolicy.visible_scope(current_user).find_by(id: id)
  end

  def render_not_found
    respond_to do |format|
      format.html { render file: Rails.root.join("public/404.html"), layout: false, status: :not_found }
      format.json { render json: { error: "Not Found" }, status: :not_found }
    end
  end
end
