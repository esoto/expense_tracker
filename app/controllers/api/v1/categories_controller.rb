# frozen_string_literal: true

module Api
  module V1
    class CategoriesController < BaseController
      def index
        categories = Category.all.order(:name)
        render json: categories.map { |c|
          {
            id: c.id,
            name: c.name,
            color: c.color,
            description: c.description
          }
        }
      end
    end
  end
end
