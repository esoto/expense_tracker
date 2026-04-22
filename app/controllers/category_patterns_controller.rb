# frozen_string_literal: true

# User-facing nested CRUD for adding/removing categorization patterns on
# a category. Authorization mirrors CategoryPolicy#manage_patterns? —
# regular users can manage patterns on their own personal categories;
# admins can manage patterns on any category.
#
# The global admin surface for browsing/filtering all patterns across the
# whole system lives at Admin::PatternsController.
class CategoryPatternsController < ApplicationController
  before_action :set_category
  before_action :authorize_manage!

  # POST /categories/:category_id/patterns
  def create
    @pattern = @category.categorization_patterns.new(
      pattern_params.merge(user_created: true)
    )

    respond_to do |format|
      if @pattern.save
        format.html { redirect_to category_path(@category), notice: "Pattern added." }
        format.turbo_stream { redirect_to category_path(@category), status: :see_other }
      else
        # Re-render the category show view with validation errors.
        @category.errors.merge!(@pattern.errors) if @pattern.errors.any?
        format.html do
          flash.now[:alert] = @pattern.errors.full_messages.to_sentence
          render "categories/show", status: :unprocessable_entity
        end
      end
    end
  end

  # DELETE /categories/:category_id/patterns/:id
  def destroy
    pattern = @category.categorization_patterns.find(params[:id])
    pattern.destroy

    redirect_to category_path(@category),
                notice: "Pattern removed.",
                status: :see_other
  end

  private

  def set_category
    @category = CategoryPolicy.visible_scope(current_user).find_by(id: params[:category_id])
    render_not_found if @category.nil?
  end

  def authorize_manage!
    return if CategoryPolicy.new(current_user, @category).manage_patterns?

    render_not_found
  end

  def pattern_params
    params.require(:categorization_pattern)
          .permit(:pattern_type, :pattern_value)
  end

  def render_not_found
    respond_to do |format|
      format.html { render file: Rails.root.join("public/404.html"), layout: false, status: :not_found }
      format.json { render json: { error: "Not Found" }, status: :not_found }
    end
  end
end
