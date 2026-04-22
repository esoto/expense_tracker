class CategoriesController < ApplicationController
  # Read actions (index/show) stay open so existing consumers (dropdowns,
  # budgets) keep working during the Personal Category Management
  # rollout. Write actions require the PR 10 feature flag.
  before_action :require_category_management_feature,
                only: %i[new create edit update destroy confirm_delete]

  before_action :set_category, only: %i[show edit update destroy confirm_delete]
  before_action :authorize_show!, only: %i[show]
  before_action :authorize_edit!, only: %i[edit update destroy confirm_delete]
  before_action :scope_parent_id, only: %i[create update]

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

  # GET /categories/:id/confirm_delete
  #
  # Shows the reassign/orphan choice page. Routed only when the category
  # has attached state that needs resolving; empty categories skip
  # straight to destroy.
  def confirm_delete
    @reassign_candidates = CategoryPolicy.visible_scope(current_user)
                                         .where.not(id: @category.id)
                                         .order(:name)
  end

  # DELETE /categories/:id
  #
  # Delegates to Services::CategoryDeletion which handles both the
  # "empty fast-path" (no dependents → plain destroy) and the full
  # reassign / orphan flows. The :strategy param chooses between them;
  # defaults to :orphan for personal categories when the user confirms
  # without selecting a target.
  def destroy
    strategy = extract_destroy_strategy
    result = Services::CategoryDeletion.new(
      category:    @category,
      actor:       current_user,
      strategy:    strategy,
      reassign_to: lookup_reassign_target
    ).call

    if result.success
      redirect_to categories_path, notice: "Category deleted.", status: :see_other
    else
      redirect_to category_path(@category),
                  alert: result.error,
                  status: :see_other
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

  def extract_destroy_strategy
    raw = params[:strategy].to_s
    return raw.to_sym if %w[reassign orphan].include?(raw)

    # Default path: shared categories must reassign (service enforces this
    # and returns a clear error); personal categories default to orphan.
    @category.shared? ? :reassign : :orphan
  end

  def lookup_reassign_target
    id = params[:reassign_to_id]
    return nil if id.blank?

    CategoryPolicy.visible_scope(current_user).find_by(id: id)
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

  # Feature-flag gate — admins always pass; everyone else needs the
  # PERSONAL_CATEGORIES_OPEN_TO_ALL env flag.
  def require_category_management_feature
    return if current_user&.can_manage_categories?

    redirect_to categories_path,
                alert: "Personal category management isn't available on your account yet.",
                status: :see_other
  end
end
