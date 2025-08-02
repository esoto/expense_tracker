require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: "Test action"
    end
  end

  describe "browser version requirements" do
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

  describe "configuration" do
    it "has browser version requirements configured" do
      # Verify the allow_browser configuration exists
      expect(ApplicationController).to respond_to(:allow_browser_versions)
    end
  end

  describe "inheritance chain" do
    it "provides base functionality for other controllers" do
      expect(ExpensesController.superclass).to eq(ApplicationController)
      expect(Api::WebhooksController.superclass).to eq(ApplicationController)
    end
  end
end