# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/composite_patterns/new.html.erb", type: :view, unit: true do
  let(:category) { create(:category) }
  let(:available_pattern) { create(:categorization_pattern, category: category) }
  let(:composite_pattern) do
    CompositePattern.new(
      operator: "AND",
      confidence_weight: CompositePattern::DEFAULT_CONFIDENCE_WEIGHT,
      active: true,
      user_created: true
    )
  end

  before do
    assign(:composite_pattern, composite_pattern)
    assign(:categories, [ category ])
    assign(:available_patterns, [ available_pattern ])
  end

  it "renders the new composite pattern heading" do
    render
    expect(rendered).to include("Nuevo Patrón Compuesto")
  end

  it "renders the subtitle" do
    render
    expect(rendered).to include("combina múltiples patrones")
  end

  it "renders breadcrumb link to composite patterns index" do
    render
    expect(rendered).to have_css("a[href='#{admin_composite_patterns_path}']")
  end

  it "renders breadcrumb 'Nuevo' label" do
    render
    expect(rendered).to include("Nuevo")
  end

  it "renders the form partial" do
    render
    expect(rendered).to have_css("form")
  end

  it "renders the name field" do
    render
    expect(rendered).to have_field("composite_pattern[name]")
  end

  it "renders the category select" do
    render
    expect(rendered).to have_select("composite_pattern[category_id]")
  end

  it "includes the category option" do
    render
    expect(rendered).to have_select("composite_pattern[category_id]", with_options: [ category.name ])
  end

  it "renders the operator select" do
    render
    expect(rendered).to have_select("composite_pattern[operator]")
  end

  it "renders operator options AND, OR, NOT" do
    render
    expect(rendered).to include("AND")
    expect(rendered).to include("OR")
    expect(rendered).to include("NOT")
  end

  it "renders the pattern_ids multi-select" do
    render
    expect(rendered).to have_css("select[multiple][name='composite_pattern[pattern_ids][]']")
  end

  it "includes available pattern in multi-select" do
    render
    expect(rendered).to include(available_pattern.pattern_value)
  end

  it "renders the confidence weight range slider" do
    render
    expect(rendered).to have_css("input[type='range'][name='composite_pattern[confidence_weight]']")
  end

  it "renders the active checkbox" do
    render
    expect(rendered).to have_field("composite_pattern[active]", type: :checkbox)
  end

  it "renders the submit button with create label" do
    render
    expect(rendered).to have_button("Crear Patrón Compuesto")
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

  context "when composite pattern has errors" do
    before do
      composite_pattern.errors.add(:name, "no puede estar en blanco")
    end

    it "renders the error summary" do
      render
      expect(rendered).to include("Por favor, corrige los siguientes errores")
    end

    it "renders the specific error message" do
      render
      expect(rendered).to include("no puede estar en blanco")
    end

    it "renders the error container with rose styling" do
      render
      expect(rendered).to include("bg-rose-50")
      expect(rendered).to include("border-rose-200")
    end
  end
end
