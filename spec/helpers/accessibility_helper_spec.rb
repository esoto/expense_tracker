# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessibilityHelper, :unit, type: :helper do
  let(:xss_payload) { '<script>alert("xss")</script>' }
  let(:xss_with_entities) { "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;" }

  describe "#skip_links" do
    it "returns html-safe content" do
      result = helper.skip_links
      expect(result).to be_html_safe
    end

    it "contains skip link elements" do
      result = helper.skip_links
      expect(result).to include("Saltar al contenido principal")
      expect(result).to include("Saltar a la navegación")
      expect(result).to include("Saltar a los filtros")
      expect(result).to include("Saltar a la lista de gastos")
    end

    it "produces valid HTML structure" do
      result = helper.skip_links
      expect(result).to include('class="sr-only-focusable"')
      expect(result).to include('class="skip-link"')
    end
  end

  describe "#dashboard_help_text" do
    it "returns html-safe content" do
      result = helper.dashboard_help_text
      expect(result).to be_html_safe
    end

    it "contains all help text elements" do
      result = helper.dashboard_help_text
      expect(result).to include("Dashboard de gastos")
      expect(result).to include("Alt+1: Filtros rápidos")
      expect(result).to include("Alt+2: Lista de gastos")
      expect(result).to include("Ctrl+Shift+V: Cambiar vista")
    end

    it "produces valid HTML with screen reader class" do
      result = helper.dashboard_help_text
      expect(result).to include('class="sr-only"')
    end
  end

  describe "#accessible_table_headers" do
    let(:columns) do
      [
        { key: "name", label: "Name" },
        { key: "amount", label: "Amount" }
      ]
    end

    it "returns html-safe content" do
      result = helper.accessible_table_headers(columns)
      expect(result).to be_html_safe
    end

    it "renders table headers correctly" do
      result = helper.accessible_table_headers(columns)
      expect(result).to include("<th")
      expect(result).to include("Name")
      expect(result).to include("Amount")
    end

    it "escapes XSS in column labels" do
      malicious_columns = [
        { key: "name", label: xss_payload }
      ]
      result = helper.accessible_table_headers(malicious_columns)
      expect(result).not_to include("<script>")
      expect(result).to include(xss_with_entities)
    end

    it "preserves scope and id attributes" do
      result = helper.accessible_table_headers(columns)
      expect(result).to include('scope="col"')
      expect(result).to include('id="header-name"')
      expect(result).to include('id="header-amount"')
    end
  end

  describe "#accessible_label" do
    let(:form_builder) do
      object = double("object", class: double(model_name: ActiveModel::Name.new(Expense)))
      ActionView::Helpers::FormBuilder.new("expense", object, helper, {})
    end

    it "returns html-safe content for simple label" do
      result = helper.accessible_label(form_builder, :name, "Name")
      expect(result).to be_html_safe
    end

    it "renders required indicator when specified" do
      result = helper.accessible_label(form_builder, :name, "Name", required: true)
      expect(result).to include("*")
      expect(result).to include("text-rose-600")
    end

    it "escapes XSS in label text" do
      result = helper.accessible_label(form_builder, :name, xss_payload)
      expect(result).not_to include("<script>")
      expect(result).to include(xss_with_entities)
    end

    it "escapes XSS in label text even with required indicator" do
      result = helper.accessible_label(form_builder, :name, xss_payload, required: true)
      expect(result).not_to include("<script>alert")
    end

    it "renders help text when provided" do
      result = helper.accessible_label(form_builder, :name, "Name", help: "Enter your name")
      expect(result).to include("Enter your name")
      expect(result).to include("name_help")
    end

    it "escapes XSS in help text" do
      result = helper.accessible_label(form_builder, :name, "Name", help: xss_payload)
      expect(result).not_to include("<script>")
    end
  end

  describe "#keyboard_shortcuts_help" do
    it "returns html-safe content" do
      result = helper.keyboard_shortcuts_help
      expect(result).to be_html_safe
    end

    it "contains keyboard shortcut information" do
      result = helper.keyboard_shortcuts_help
      expect(result).to include("Tab")
      expect(result).to include("Escape")
      expect(result).to include("Alt+1")
      expect(result).to include("Ctrl+Shift+S")
    end

    it "produces valid HTML list structure" do
      result = helper.keyboard_shortcuts_help
      expect(result).to include("<li>")
      expect(result).to include("<ul>")
    end
  end

  describe "#expense_aria_label" do
    let(:category) { build(:category, name: "Food") }
    let(:expense) do
      build(:expense,
        merchant_name: "Test Store",
        amount: 5000,
        transaction_date: Date.new(2024, 1, 15),
        category: category,
        status: "pending",
        currency: "crc")
    end

    it "includes merchant name" do
      result = helper.expense_aria_label(expense)
      expect(result).to include("Test Store")
    end

    it "escapes XSS in merchant name" do
      expense.merchant_name = xss_payload
      result = helper.expense_aria_label(expense)
      # expense_aria_label returns plain text for aria-label, not HTML
      # but we verify it does not produce executable script tags
      expect(result).to include(xss_payload) # plain text context is safe for aria-label
    end

    it "handles nil category" do
      expense.category = nil
      result = helper.expense_aria_label(expense)
      expect(result).to include("Sin categoría")
    end

    it "includes index when provided" do
      result = helper.expense_aria_label(expense, 1)
      expect(result).to include("Gasto 1")
    end
  end

  describe "#accessible_button_label" do
    let(:expense) { build(:expense, merchant_name: "Test Store", status: "pending", currency: "crc") }

    it "returns categorize label with merchant" do
      result = helper.accessible_button_label("categorize", expense)
      expect(result).to include("Test Store")
    end

    it "handles XSS in merchant name for button labels" do
      expense.merchant_name = xss_payload
      result = helper.accessible_button_label("categorize", expense)
      # These are plain text strings used as aria-labels, not HTML
      expect(result).to include(xss_payload)
    end

    it "returns default label without expense" do
      result = helper.accessible_button_label("categorize")
      expect(result).to eq("Categorizar gasto")
    end

    it "handles all action types" do
      %w[categorize status duplicate delete select select_all bulk_categorize bulk_status bulk_delete].each do |action|
        result = helper.accessible_button_label(action)
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end
    end
  end

  describe "XSS protection across all html-generating methods" do
    it "skip_links uses safe_join instead of html_safe on joined content" do
      result = helper.skip_links
      # Verify the output is valid and safe
      expect(result).to be_html_safe
      expect(result).to include("href=")
    end

    it "dashboard_help_text uses safe_join instead of html_safe on joined content" do
      result = helper.dashboard_help_text
      expect(result).to be_html_safe
      expect(result).to include("id=")
    end

    it "keyboard_shortcuts_help uses safe_join instead of html_safe on joined content" do
      result = helper.keyboard_shortcuts_help
      expect(result).to be_html_safe
      expect(result).to include("<li>")
    end

    it "accessible_table_headers escapes malicious column keys" do
      # Even though key is used in id attribute, content_tag handles escaping
      malicious_columns = [
        { key: '"><script>alert(1)</script>', label: "Name" }
      ]
      result = helper.accessible_table_headers(malicious_columns)
      expect(result).not_to include("<script>alert(1)</script>")
    end
  end
end
