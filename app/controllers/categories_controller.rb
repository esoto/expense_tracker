class CategoriesController < ApplicationController
  # GET /categories.json
  def index
    @categories = Category.order(:name)
    
    respond_to do |format|
      format.json do
        render json: @categories.map { |category|
          {
            id: category.id,
            name: category.name,
            color: category.color,
            parent_id: category.parent_id
          }
        }
      end
      format.html { redirect_to expenses_path }
    end
  end
end