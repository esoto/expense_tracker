module Api
  module V1
    class CategoriesController < ApplicationController
      skip_before_action :authenticate_user!
      skip_before_action :verify_authenticity_token

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
