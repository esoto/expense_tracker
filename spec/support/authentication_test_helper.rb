# frozen_string_literal: true

# Test helper for controller authentication
module AuthenticationTestHelper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def setup_authentication_mocks
      before do
        # Define authenticate_user! as a no-op if it doesn't exist
        unless controller.respond_to?(:authenticate_user!)
          controller.class.define_method(:authenticate_user!) { true }
        end

        # Define current_user if it doesn't exist
        unless controller.respond_to?(:current_user)
          controller.class.define_method(:current_user) { nil }
        end
      end
    end
  end

  def mock_user_authentication(user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:authenticate_user!).and_return(true)
  end
end

RSpec.configure do |config|
  config.include AuthenticationTestHelper, type: :controller
end
