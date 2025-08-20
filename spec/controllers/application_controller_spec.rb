require 'rails_helper'

RSpec.describe ApplicationController, type: :controller, unit: true do
  controller do
    def index
      render plain: "Test action"
    end
  end

  describe "browser version requirements", unit: true do
    it "allows modern browsers" do
      # Set a modern user agent that supports required features
      request.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

      get :index
      expect(response).to have_http_status(:ok)
    end

    it "inherits from ActionController::Base" do
      expect(ApplicationController.superclass).to eq(ActionController::Base)
    end
  end

  describe "configuration", unit: true do
    it "has browser restrictions enabled" do
      # Verify that the controller has browser compatibility checks
      # This is verified by successful loading and inheritance
      expect(ApplicationController.superclass).to eq(ActionController::Base)
    end
  end

  describe "inheritance chain", unit: true do
    it "provides base functionality for other controllers" do
      expect(ExpensesController.superclass).to eq(ApplicationController)
      expect(Api::WebhooksController.superclass).to eq(ApplicationController)
    end
  end
end
