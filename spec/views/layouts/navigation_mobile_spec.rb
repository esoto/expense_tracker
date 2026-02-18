# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Navigation mobile responsiveness", type: :controller, unit: true do
  render_views

  controller(ExpensesController) do
    # Use ExpensesController as a representative controller that renders the layout
  end

  let(:admin_user) { create(:admin_user, :with_session) }
  let!(:email_account) { create(:email_account) }

  before do
    authenticate_admin_in_controller(admin_user)
    get :index
  end

  describe "mobile nav Stimulus controller" do
    it "attaches mobile-nav controller to the nav element" do
      expect(response.body).to include('data-controller="mobile-nav"')
    end
  end

  describe "hamburger button" do
    it "renders a hamburger button visible only on mobile" do
      expect(response.body).to include('md:hidden')
      expect(response.body).to include('data-mobile-nav-target="button"')
    end

    it "has correct toggle action binding" do
      expect(response.body).to include('data-action="click->mobile-nav#toggle"')
    end

    it "has aria-expanded attribute set to false" do
      expect(response.body).to include('aria-expanded="false"')
    end

    it "has aria-controls pointing to mobile-menu" do
      expect(response.body).to include('aria-controls="mobile-menu"')
    end

    it "has an accessible label for the button" do
      expect(response.body).to include('aria-label="Abrir menú de navegación"')
    end

    it "contains a hamburger SVG icon with aria-hidden" do
      expect(response.body).to include('M4 6h16M4 12h16M4 18h16')
      expect(response.body).to include('aria-hidden="true"')
    end
  end

  describe "desktop navigation links" do
    it "hides desktop links on mobile with hidden md:flex" do
      expect(response.body).to match(/class="hidden md:flex[^"]*"/)
    end

    it "contains all navigation links in the desktop menu" do
      expect(response.body).to include("Dashboard")
      expect(response.body).to include("Gastos")
      expect(response.body).to include("Categorizar")
      expect(response.body).to include("Analytics")
      expect(response.body).to include("Cuentas")
      expect(response.body).to include("Sincronización")
      expect(response.body).to include("Patrones")
      expect(response.body).to include("Nuevo Gasto")
    end
  end

  describe "mobile dropdown menu" do
    it "renders a mobile menu container with correct id" do
      expect(response.body).to include('id="mobile-menu"')
    end

    it "attaches the menu target to mobile-nav controller" do
      expect(response.body).to include('data-mobile-nav-target="menu"')
    end

    it "is hidden by default with hidden md:hidden classes" do
      expect(response.body).to match(/id="mobile-menu"[^>]*class="hidden md:hidden/)
    end

    it "has role=navigation for semantic accessibility" do
      expect(response.body).to include('role="navigation"')
    end

    it "has aria-label for the mobile menu" do
      expect(response.body).to include('aria-label="Menú de navegación móvil"')
    end

    it "uses semantic navigation markup without menu roles" do
      mobile_menu_match = response.body.match(/id="mobile-menu".*?<\/div>\s*<\/div>/m)
      expect(mobile_menu_match).to be_present
      mobile_menu_html = mobile_menu_match[0]
      expect(mobile_menu_html).not_to include('role="menuitem"')
    end

    it "contains all navigation links in the mobile menu" do
      # Parse the mobile menu section specifically
      mobile_menu_match = response.body.match(/id="mobile-menu".*?<\/div>\s*<\/div>/m)
      expect(mobile_menu_match).to be_present

      mobile_menu_html = mobile_menu_match[0]
      expect(mobile_menu_html).to include("Dashboard")
      expect(mobile_menu_html).to include("Gastos")
      expect(mobile_menu_html).to include("Categorizar")
      expect(mobile_menu_html).to include("Analytics")
      expect(mobile_menu_html).to include("Cuentas")
      expect(mobile_menu_html).to include("Sincronización")
      expect(mobile_menu_html).to include("Patrones")
      expect(mobile_menu_html).to include("Nuevo Gasto")
    end
  end

  describe "Financial Confidence color palette compliance" do
    it "uses teal-700 for primary actions" do
      expect(response.body).to include("bg-teal-700")
    end

    it "uses teal-50 for active states" do
      expect(response.body).to include("bg-teal-50")
    end

    it "uses slate-600 for secondary text" do
      expect(response.body).to include("text-slate-600")
    end

    it "uses slate-200 for borders" do
      expect(response.body).to include("border-slate-200")
    end

    it "uses teal-500 for focus ring on hamburger button" do
      expect(response.body).to include("focus:ring-teal-500")
    end

    it "does not use default blue colors" do
      # Extract just the nav section to check
      nav_match = response.body.match(/<nav.*?<\/nav>/m)
      expect(nav_match).to be_present
      nav_html = nav_match[0]

      expect(nav_html).not_to include("blue-500")
      expect(nav_html).not_to include("blue-600")
      expect(nav_html).not_to include("blue-700")
    end
  end

  describe "responsive design" do
    it "has desktop links visible only on md+ screens" do
      expect(response.body).to match(/class="hidden md:flex[^"]*"/)
    end

    it "has hamburger button visible only on mobile" do
      expect(response.body).to match(/class="md:hidden inline-flex[^"]*"/)
    end

    it "has mobile menu hidden on md+ screens" do
      expect(response.body).to match(/id="mobile-menu"[^>]*class="hidden md:hidden/)
    end
  end
end
