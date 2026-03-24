# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, "pagination", type: :helper, unit: true do
  describe "#pagy_financial_nav", unit: true do
    before do
      # Stub the request object for URL generation
      allow(helper).to receive(:request).and_return(
        double(
          query_parameters: {},
          path: "/expenses"
        )
      )
    end

    context "when there is only one page" do
      it "returns an empty string" do
        pagy = Pagy::Offset.new(count: 10, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to eq("")
      end
    end

    context "when there are multiple pages" do
      it "renders a nav element with pagination links" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include('<nav aria-label="Paginación"')
      end

      it "renders page number links" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("page=2")
        expect(result).to include("page=3")
      end

      it "highlights the current page with teal-700 background" do
        pagy = Pagy::Offset.new(count: 150, page: 2, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("bg-teal-700")
        expect(result).to include('aria-current="page"')
      end

      it "does not use blue colors" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).not_to include("blue-")
      end

      it "uses the Financial Confidence color palette classes" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("text-slate-700")
        expect(result).to include("border-slate-200")
        expect(result).to include("hover:bg-teal-50")
        expect(result).to include("hover:text-teal-700")
      end
    end

    context "when on the first page" do
      it "disables the previous button" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        # The previous button should be a disabled span, not a link
        expect(result).to include("cursor-not-allowed")
        expect(result).to include("Anterior")
      end

      it "enables the next button as a link" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("Siguiente")
        expect(result).to include("page=2")
      end
    end

    context "when on the last page" do
      it "enables the previous button as a link" do
        pagy = Pagy::Offset.new(count: 150, page: 3, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("Anterior")
        expect(result).to include("page=2")
      end

      it "disables the next button" do
        pagy = Pagy::Offset.new(count: 150, page: 3, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        # The next disabled span should appear after the page links
        expect(result).to include("cursor-not-allowed")
        expect(result).to include("Siguiente")
        # Ensure "Siguiente" is NOT a link (no href for the next button)
        expect(result).not_to include('page=4')
      end
    end

    context "when on a middle page" do
      it "enables both previous and next buttons as links" do
        pagy = Pagy::Offset.new(count: 150, page: 2, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("page=1")
        expect(result).to include("page=3")
      end
    end

    context "when there are many pages (gap rendering)" do
      it "renders gap indicators for distant pages" do
        pagy = Pagy::Offset.new(count: 1000, page: 10, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("...")
      end

      it "always shows the first page" do
        pagy = Pagy::Offset.new(count: 1000, page: 10, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include(">1</a>")
      end

      it "always shows the last page" do
        pagy = Pagy::Offset.new(count: 1000, page: 10, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include(">20</a>")
      end
    end

    context "preserving query parameters" do
      it "includes existing query parameters in pagination links" do
        allow(helper).to receive(:request).and_return(
          double(
            query_parameters: { "category" => "food", "bank" => "BAC" },
            path: "/expenses"
          )
        )
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include("category=food")
        expect(result).to include("bank=BAC")
      end
    end

    context "accessibility" do
      it "includes aria-label on the nav element" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include('aria-label="Paginación"')
      end

      it "includes aria-current on the active page" do
        pagy = Pagy::Offset.new(count: 150, page: 2, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include('aria-current="page"')
      end

      it "includes aria-label on page links" do
        pagy = Pagy::Offset.new(count: 150, page: 1, limit: 50)

        result = helper.pagy_financial_nav(pagy)

        expect(result).to include('aria-label="Ir a página')
      end
    end
  end

  describe "#build_page_series", unit: true do
    it "returns all pages when total is 9 or fewer" do
      pagy = Pagy::Offset.new(count: 400, page: 1, limit: 50)

      series = helper.send(:build_page_series, pagy)

      expect(series).to eq([ 1, 2, 3, 4, 5, 6, 7, 8 ])
    end

    it "includes gaps for many pages when on page 1" do
      pagy = Pagy::Offset.new(count: 1000, page: 1, limit: 50)

      series = helper.send(:build_page_series, pagy)

      expect(series.first).to eq(1)
      expect(series.last).to eq(20)
      expect(series).to include(:gap)
    end

    it "includes gaps on both sides for a middle page" do
      pagy = Pagy::Offset.new(count: 1000, page: 10, limit: 50)

      series = helper.send(:build_page_series, pagy)

      expect(series.first).to eq(1)
      expect(series.last).to eq(20)
      expect(series.count(:gap)).to eq(2)
      expect(series).to include(8, 9, 10, 11, 12)
    end

    it "includes gap only on the left for the last page" do
      pagy = Pagy::Offset.new(count: 1000, page: 20, limit: 50)

      series = helper.send(:build_page_series, pagy)

      expect(series.first).to eq(1)
      expect(series.last).to eq(20)
      expect(series.count(:gap)).to eq(1)
    end
  end
end
