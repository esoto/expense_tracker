# frozen_string_literal: true

require "rails_helper"

# PER-184: Dashboard charts crash — Chart.js date-fns adapter undefined
#
# Root cause: application.js imported "chartjs-adapter-date-fns" via the
# UMD bundle (.bundle.min.js).  That build expects window.Chart to be set
# globally, but Chart.js loaded as an ES module via import-maps never
# populates window.Chart.  Result: TypeError at module evaluation time,
# crashing every chart on the dashboard.
#
# Fix: remove the adapter import entirely.  None of the chart controllers use
# type:'time' axes, so the adapter was dead code.
#
# These specs guard the fix at the HTTP/HTML layer:
#   • Dashboard responds 200 and contains the chart canvas elements
#   • The importmap does NOT reference the broken adapter bundle URL
#   • application.js does NOT import the adapter
RSpec.describe "PER-184: Chart.js date-fns adapter regression guard", type: :request do
  let(:admin_user) { create(:admin_user) }

  before { sign_in_admin(admin_user) }

  describe "GET /expenses/dashboard", :unit do
    before do
      jobs_relation = instance_double(ActiveRecord::Relation, exists?: false, count: 0)
      intermediate  = double("scope", where: jobs_relation)
      allow(SolidQueue::Job).to receive(:where)
        .with(class_name: "ProcessEmailsJob", finished_at: nil)
        .and_return(intermediate)
    end

    it "responds with HTTP 200 (charts do not crash the page)" do
      get dashboard_expenses_path
      expect(response).to have_http_status(:success)
    end

    it "includes the Chartkick line chart canvas for monthly trend" do
      get dashboard_expenses_path
      expect(response.body).to include("Tendencia Mensual")
    end

    it "includes the Chartkick pie chart canvas for category breakdown" do
      get dashboard_expenses_path
      expect(response.body).to include("Gastos por Categoría")
    end

    it "renders the dashboard heading" do
      get dashboard_expenses_path
      expect(response.body).to include("Dashboard de Gastos")
    end
  end

  describe "importmap configuration", :unit do
    let(:importmap_content) do
      Rails.root.join("config/importmap.rb").read
    end

    it "does NOT pin the broken UMD adapter bundle that requires window.Chart" do
      expect(importmap_content).not_to include("chartjs-adapter-date-fns.bundle.min.js")
    end

    it "does NOT pin chartjs-adapter-date-fns at all (adapter is unused)" do
      expect(importmap_content).not_to match(/^pin "chartjs-adapter-date-fns"/)
    end

    it "pins chart.js via the ESM build" do
      expect(importmap_content).to include("chart.js")
      expect(importmap_content).to include("+esm")
    end
  end

  describe "application.js entrypoint", :unit do
    let(:application_js_content) do
      Rails.root.join("app/javascript/application.js").read
    end

    it "does NOT import chartjs-adapter-date-fns" do
      # Any bare 'import "chartjs-adapter-date-fns"' line would re-introduce the crash
      expect(application_js_content).not_to match(/^\s*import\s+"chartjs-adapter-date-fns"/)
    end

    it "imports chart.js" do
      expect(application_js_content).to include('import "chart.js"')
    end

    it "imports chartkick" do
      expect(application_js_content).to include('import "chartkick"')
    end
  end
end
