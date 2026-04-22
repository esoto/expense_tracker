class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]
  before_action :authorize_show!, only: %i[show]
  before_action :authorize_edit!, only: %i[edit update destroy]

  # GET /categories(.json)
  def index
    @categories = CategoryPolicy.visible_scope(current_user).order(:name)

    respond_to do |format|
      format.html
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
  def new
    @category = Category.new(user: current_user)
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
  # (no expenses, no children, no patterns). The full reassign/orphan flow is
  # the subject of PR 8 (CategoryDeletion service).
  def destroy
    if @category.expenses.exists? || @category.children.exists? || @category.categorization_patterns.exists?
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
    params.require(:category).permit(:name, :description, :color, :parent_id, :i18n_key)
  end

  def render_not_found
    respond_to do |format|
      format.html { render file: Rails.root.join("public/404.html"), layout: false, status: :not_found }
      format.json { render json: { error: "Not Found" }, status: :not_found }
    end
  end
end
