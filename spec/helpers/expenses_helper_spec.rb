require 'rails_helper'

RSpec.describe ExpensesHelper, type: :helper do
  let(:category) { create(:category, name: "Alimentación", color: "#10B981") }
  let(:expense) { create(:expense, category: category) }

  describe "#confidence_color_class" do
    it "returns correct class for high confidence" do
      expect(helper.confidence_color_class(:high))
        .to eq("bg-emerald-100 text-emerald-800 border-emerald-200")
    end

    it "returns correct class for medium confidence" do
      expect(helper.confidence_color_class(:medium))
        .to eq("bg-teal-100 text-teal-800 border-teal-200")
    end

    it "returns correct class for low confidence" do
      expect(helper.confidence_color_class(:low))
        .to eq("bg-amber-100 text-amber-800 border-amber-200")
    end

    it "returns correct class for very_low confidence" do
      expect(helper.confidence_color_class(:very_low))
        .to eq("bg-rose-100 text-rose-800 border-rose-200")
    end

    it "returns default class for unknown level" do
      expect(helper.confidence_color_class(:unknown))
        .to eq("bg-slate-100 text-slate-600 border-slate-200")
    end
  end

  describe "#expense_confidence_badge" do
    context "when ml_confidence is present" do
      before { expense.ml_confidence = 0.85 }

      it "returns a span with confidence percentage" do
        badge = helper.expense_confidence_badge(expense)
        expect(badge).to include("85%")
        expect(badge).to include("data-controller=\"category-confidence\"")
        expect(badge).to include("data-category-confidence-expense-id-value=\"#{expense.id}\"")
      end
    end

    context "when ml_confidence is nil" do
      before { expense.ml_confidence = nil }

      it "returns empty string" do
        expect(helper.expense_confidence_badge(expense)).to eq("")
      end
    end
  end

  describe "#confidence_icon" do
    it "returns check icon for high confidence" do
      icon = helper.confidence_icon(:high)
      expect(icon).to include("text-emerald-600")
      expect(icon).to include("M9 12l2 2 4-4m6")
    end

    it "returns info icon for medium confidence" do
      icon = helper.confidence_icon(:medium)
      expect(icon).to include("text-teal-600")
      expect(icon).to include("M13 16h-1v-4h-1m1-4h")
    end

    it "returns warning icon for low confidence" do
      icon = helper.confidence_icon(:low)
      expect(icon).to include("text-amber-600")
      expect(icon).to include("M12 9v2m0 4h")
    end

    it "returns question icon for unknown confidence" do
      icon = helper.confidence_icon(:unknown)
      expect(icon).to include("text-slate-400")
      expect(icon).to include("M8.228 9c.549")
    end
  end

  describe "#confidence_tooltip_text" do
    context "with ml_confidence_explanation" do
      before do
        expense.ml_confidence = 0.85
        expense.ml_confidence_explanation = "Custom explanation"
      end

      it "returns the custom explanation" do
        expect(helper.confidence_tooltip_text(expense)).to eq("Custom explanation")
      end
    end

    context "without ml_confidence_explanation" do
      it "returns appropriate text for high confidence" do
        expense.ml_confidence = 0.90
        expect(helper.confidence_tooltip_text(expense))
          .to eq("Alta confianza (90%) - Categorización muy probable")
      end

      it "returns appropriate text for medium confidence" do
        expense.ml_confidence = 0.75
        expect(helper.confidence_tooltip_text(expense))
          .to eq("Confianza media (75%) - Categorización probable")
      end

      it "returns appropriate text for low confidence" do
        expense.ml_confidence = 0.55
        expect(helper.confidence_tooltip_text(expense))
          .to eq("Baja confianza (55%) - Revisar categorización")
      end

      it "returns appropriate text for very low confidence" do
        expense.ml_confidence = 0.30
        expect(helper.confidence_tooltip_text(expense))
          .to eq("Muy baja confianza (30%) - Requiere revisión manual")
      end

      it "returns appropriate text for no confidence" do
        expense.ml_confidence = nil
        expect(helper.confidence_tooltip_text(expense))
          .to eq("Sin información de confianza")
      end
    end
  end

  describe "#expense_category_badge" do
    context "with category" do
      it "returns a styled span with category name" do
        badge = helper.expense_category_badge(expense)
        expect(badge).to include(category.name)
        expect(badge).to include("background-color: #{category.color}20")
        expect(badge).to include("color: #{category.color}")
      end
    end

    context "without category" do
      before { expense.category = nil }

      it "returns a span with 'Sin categoría'" do
        badge = helper.expense_category_badge(expense)
        expect(badge).to include("Sin categoría")
        expect(badge).to include("bg-slate-100 text-slate-600")
      end
    end
  end

  describe "#learning_indicator" do
    context "when recently corrected" do
      before { expense.ml_last_corrected_at = 30.minutes.ago }

      it "returns learning emoji indicator" do
        indicator = helper.learning_indicator(expense)
        expect(indicator).to include("📚")
        expect(indicator).to include("Sistema aprendiendo")
      end
    end

    context "when corrected more than 1 hour ago" do
      before { expense.ml_last_corrected_at = 2.hours.ago }

      it "returns empty string" do
        expect(helper.learning_indicator(expense)).to eq("")
      end
    end

    context "when never corrected" do
      before { expense.ml_last_corrected_at = nil }

      it "returns empty string" do
        expect(helper.learning_indicator(expense)).to eq("")
      end
    end
  end

  describe "#mobile_confidence_display" do
    context "when ml_confidence is present" do
      before { expense.ml_confidence = 0.75 }

      it "returns mobile-optimized confidence display" do
        display = helper.mobile_confidence_display(expense)
        expect(display).to include("Confianza:")
        expect(display).to include("75%")
        expect(display).to include("text-teal-600")
      end
    end

    context "when ml_confidence is nil" do
      before { expense.ml_confidence = nil }

      it "returns empty string" do
        expect(helper.mobile_confidence_display(expense)).to eq("")
      end
    end
  end
end
