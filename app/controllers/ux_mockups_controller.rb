class UxMockupsController < ApplicationController
  layout "mockup", except: :index

  def index
    # List all available mockups - uses default application layout
  end

  def mobile_expense_cards
    render "expenses/mobile_expense_card_mockup"
  end

  def sync_status_dashboard
    render "expenses/sync_status_mockup"
  end

  def inline_categorization
    render "expenses/inline_category_mockup"
  end

  def color_palettes
    render "expenses/color_palette_mockup"
  end
end
