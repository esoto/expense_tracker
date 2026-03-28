# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/composite_patterns/edit.html.erb", type: :view, unit: true do
  let(:category) { create(:category) }
  let(:available_pattern) { create(:categorization_pattern, category: category) }
  let(:composite_pattern) do
    create(:composite_pattern,
      category: category,
      name: "Test Composite",
      operator: "OR",
      active: true,
      pattern_ids: [ available_pattern.id ]
    )
  end

  before do
    assign(:composite_pattern, composite_pattern)
    assign(:categories, [ category ])
    assign(:available_patterns, [ available_pattern ])
    assign(:selected_patterns, composite_pattern.component_patterns)
  end

  it "renders the edit composite pattern heading" do
    render
    expect(rendered).to include("Editar Patrón Compuesto")
  end

  it "renders the subtitle with pattern name" do
    render
    expect(rendered).to include("Test Composite")
  end

  it "renders breadcrumb link to composite patterns index" do
    render
    expect(rendered).to have_css("a[href='#{admin_composite_patterns_path}']")
  end

  it "renders breadcrumb link to the composite pattern show page" do
    render
    expect(rendered).to have_css("a[href='#{admin_composite_pattern_path(composite_pattern)}']")
  end

  it "renders the form partial" do
    render
    expect(rendered).to have_css("form")
  end

  it "renders the name field pre-populated" do
    render
    expect(rendered).to have_field("composite_pattern[name]", with: "Test Composite")
  end

  it "renders the category select with current value selected" do
    render
    expect(rendered).to have_select("composite_pattern[category_id]", selected: category.name)
  end

  it "renders the operator select with current value selected" do
    render
    expect(rendered).to have_select("composite_pattern[operator]", selected: "OR — Cualquier patrón debe coincidir")
  end

  it "renders the pattern_ids multi-select" do
    render
    expect(rendered).to have_css("select[multiple][name='composite_pattern[pattern_ids][]']")
  end

  it "renders the confidence weight range slider" do
    render
    expect(rendered).to have_css("input[type='range'][name='composite_pattern[confidence_weight]']")
  end

  it "renders the active checkbox" do
    render
    expect(rendered).to have_field("composite_pattern[active]", type: :checkbox)
  end

  it "renders the submit button with update label" do
    render
    expect(rendered).to have_button("Actualizar Patrón Compuesto")
  end

  it "renders the cancel link" do
    render
    expect(rendered).to have_link("Cancelar", href: admin_composite_patterns_path)
  end

  it "uses Financial Confidence color palette (teal primary button)" do
    render
    expect(rendered).to include("bg-teal-700")
  end

  it "uses card layout style" do
    render
    expect(rendered).to include("bg-white rounded-xl shadow-sm border border-slate-200")
  end

  context "when composite pattern has no usage history" do
    before do
      composite_pattern.update_columns(usage_count: 0)
    end

    it "does not render the usage warning banner" do
      render
      expect(rendered).not_to include("Patrón en uso activo")
    end
  end

  context "when composite pattern has usage history" do
    before do
      composite_pattern.update_columns(usage_count: 25, success_count: 20, success_rate: 0.8)
    end

    it "renders the usage warning banner" do
      render
      expect(rendered).to include("Patrón en uso activo")
    end

    it "shows usage count in warning" do
      render
      expect(rendered).to include("25")
    end

    it "shows success rate in warning" do
      render
      expect(rendered).to include("80%")
    end

    it "renders warning with amber styling" do
      render
      expect(rendered).to include("bg-amber-50")
      expect(rendered).to include("border-amber-200")
    end
  end

  context "when composite pattern has errors" do
    before do
      composite_pattern.errors.add(:pattern_ids, "no puede estar en blanco")
    end

    it "renders the error summary" do
      render
      expect(rendered).to include("Por favor, corrige los siguientes errores")
    end

    it "renders the specific error message" do
      render
      expect(rendered).to include("no puede estar en blanco")
    end
  end

  context "when editing with multiple available patterns" do
    let(:second_pattern) { create(:categorization_pattern, category: category) }

    before do
      assign(:available_patterns, [ available_pattern, second_pattern ])
    end

    it "shows all available patterns in multi-select" do
      render
      expect(rendered).to include(available_pattern.pattern_value)
      expect(rendered).to include(second_pattern.pattern_value)
    end
  end
end
