require 'rails_helper'

RSpec.describe "expenses/dashboard.html.erb", type: :view do
  let(:email_account) { create(:email_account) }
  let(:metrics_data) do
    {
      period: :month,
      reference_date: Date.current,
      date_range: Date.current.beginning_of_month..Date.current.end_of_month,
      metrics: {
        total_amount: 125000.0,
        transaction_count: 42,
        average_amount: 2976.19,
        median_amount: 2500.0,
        min_amount: 100.0,
        max_amount: 15000.0,
        unique_merchants: 18,
        unique_categories: 7,
        uncategorized_count: 3,
        by_status: { "processed" => 40, "pending" => 2 },
        by_currency: { "crc" => 120000.0, "usd" => 5000.0 }
      },
      trends: {
        amount_change: 12.5,
        count_change: 8.3,
        average_change: 3.8,
        absolute_amount_change: 14062.5,
        absolute_count_change: 3,
        is_increase: true,
        previous_period_total: 110937.5,
        previous_period_count: 39
      },
      category_breakdown: [],
      daily_breakdown: {},
      calculated_at: Time.current
    }
  end

  before do
    # Assign required instance variables
    assign(:total_metrics, metrics_data)
    assign(:month_metrics, metrics_data)
    assign(:week_metrics, metrics_data.merge(
      metrics: metrics_data[:metrics].merge(total_amount: 28500.0, transaction_count: 12)
    ))
    assign(:day_metrics, metrics_data.merge(
      metrics: metrics_data[:metrics].merge(total_amount: 5200.0, transaction_count: 3)
    ))

    # Legacy variables
    assign(:total_expenses, 125000.0)
    assign(:expense_count, 42)
    assign(:current_month_total, 125000.0)
    assign(:last_month_total, 110937.5)

    # Other required variables
    assign(:recent_expenses, [])
    assign(:category_totals, {})
    assign(:sorted_categories, [])
    assign(:monthly_data, {})
    assign(:bank_totals, [])
    assign(:top_merchants, [])
    assign(:email_accounts, [ email_account ])
    assign(:last_sync_info, {})
    assign(:active_sync_session, nil)
    assign(:last_completed_sync, nil)
    assign(:primary_email_account, email_account)
  end

  it "renders the enhanced primary metric card" do
    render

    # Check for the primary metric card with gradient background
    expect(rendered).to have_css('.bg-gradient-to-br.from-teal-700.to-teal-800')

    # Check for the "TOTAL DE GASTOS" heading
    expect(rendered).to have_content('TOTAL DE GASTOS')

    # Check for animated metric controller (can be combined with other controllers)
    expect(rendered).to have_css('[data-controller*="animated-metric"]')

    # Check for tooltip controller on the same element
    expect(rendered).to have_css('[data-controller*="tooltip"]')

    # Check for the value target
    expect(rendered).to have_css('[data-animated-metric-target="value"]')

    # Check for trend indicator
    expect(rendered).to have_css('[data-animated-metric-target="trend"]')

    # Check for sparkline target
    expect(rendered).to have_css('[data-animated-metric-target="sparkline"]')
  end

  it "renders the three secondary metric cards" do
    render

    # Check for "Este Mes" card
    expect(rendered).to have_content('Este Mes')

    # Check for "Esta Semana" card
    expect(rendered).to have_content('Esta Semana')

    # Check for "Hoy" card
    expect(rendered).to have_content('Hoy')

    # Verify grid layout for secondary cards
    expect(rendered).to have_css('.grid.grid-cols-1.md\\:grid-cols-3')
  end

  it "displays transaction counts in secondary cards" do
    render

    # Check for transaction count displays
    expect(rendered).to match(/\d+ transacciones/)
  end

  it "includes proper trend indicators" do
    render

    # Check for increase indicator
    expect(rendered).to have_css('.text-rose-600', text: /\+/)

    # Check for trend percentage
    expect(rendered).to have_content('12.5%')
  end

  it "shows additional statistics in primary card" do
    render

    # Check for additional stats section
    expect(rendered).to have_content('Transacciones')
    expect(rendered).to have_content('Promedio')
    expect(rendered).to have_content('Categorías')
  end

  it "applies hover effects to metric cards" do
    render

    # Check for hover classes that are actually used in the template
    expect(rendered).to have_css('.hover\\:shadow-lg')
    expect(rendered).to have_css('.hover\\:-translate-y-1')
  end

  it "includes proper icons for each metric type" do
    render

    # Check for SVG icons
    expect(rendered).to have_css('svg', minimum: 4)
  end

  it "maintains responsive design" do
    render

    # Check for responsive grid classes
    expect(rendered).to have_css('.grid-cols-1')
    expect(rendered).to have_css('.md\\:grid-cols-3')
  end
end
