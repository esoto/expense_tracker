module ExpensesHelper
  # Returns the appropriate color class based on confidence level
  def confidence_color_class(confidence_level)
    case confidence_level
    when :high
      "bg-emerald-100 text-emerald-800 border-emerald-200"
    when :medium
      "bg-teal-100 text-teal-800 border-teal-200"
    when :low
      "bg-amber-100 text-amber-800 border-amber-200"
    when :very_low
      "bg-rose-100 text-rose-800 border-rose-200"
    else
      "bg-slate-100 text-slate-600 border-slate-200"
    end
  end

  # Returns the confidence badge HTML
  def expense_confidence_badge(expense)
    return "" unless expense.ml_confidence.present?

    level = expense.confidence_level
    percentage = expense.confidence_percentage
    color_class = confidence_color_class(level)

    content_tag :span,
                "#{percentage}%",
                class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border #{color_class}",
                data: {
                  controller: "category-confidence",
                  category_confidence_expense_id_value: expense.id,
                  category_confidence_level_value: level.to_s,
                  category_confidence_percentage_value: percentage,
                  category_confidence_explanation_value: expense.ml_confidence_explanation || ""
                },
                title: confidence_tooltip_text(expense)
  end

  # Returns the confidence icon based on level
  def confidence_icon(confidence_level)
    case confidence_level
    when :high
      content_tag(:svg, class: "w-4 h-4 text-emerald-600", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
      end
    when :medium
      content_tag(:svg, class: "w-4 h-4 text-teal-600", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
      end
    when :low, :very_low
      content_tag(:svg, class: "w-4 h-4 text-amber-600", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z")
      end
    else
      content_tag(:svg, class: "w-4 h-4 text-slate-400", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
        content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z")
      end
    end
  end

  # Returns tooltip text for confidence display
  def confidence_tooltip_text(expense)
    if expense.ml_confidence_explanation.present?
      expense.ml_confidence_explanation
    else
      case expense.confidence_level
      when :high
        "Alta confianza (#{expense.confidence_percentage}%) - Categorización muy probable"
      when :medium
        "Confianza media (#{expense.confidence_percentage}%) - Categorización probable"
      when :low
        "Baja confianza (#{expense.confidence_percentage}%) - Revisar categorización"
      when :very_low
        "Muy baja confianza (#{expense.confidence_percentage}%) - Requiere revisión manual"
      else
        "Sin información de confianza"
      end
    end
  end

  # Returns the category display with confidence indicator
  def category_with_confidence(expense)
    return expense_category_badge(expense) unless expense.ml_confidence.present?

    content_tag :div, class: "inline-flex items-center gap-1", data: { turbo_frame: "expense_#{expense.id}_category" } do
      concat expense_category_badge(expense)
      concat expense_confidence_badge(expense)
      if expense.needs_review?
        concat content_tag(:button,
                          confidence_icon(:low),
                          class: "ml-1 hover:bg-amber-50 rounded p-0.5 transition-colors",
                          data: {
                            action: "click->category-confidence#showCorrection",
                            category_confidence_target: "correctionTrigger"
                          },
                          title: "Corregir categoría")
      end
    end
  end

  # Returns a simple category badge
  def expense_category_badge(expense)
    if expense.category
      content_tag :span,
                  expense.category.name,
                  class: "inline-flex px-2 py-1 text-xs font-medium rounded-full",
                  style: "background-color: #{expense.category.color}20; color: #{expense.category.color};"
    else
      content_tag :span,
                  "Sin categoría",
                  class: "inline-flex px-2 py-1 text-xs font-medium rounded-full bg-slate-100 text-slate-600"
    end
  end

  # Returns suggested category display
  def suggested_category_display(expense)
    return "" unless expense.ml_suggested_category_id.present?

    suggested = expense.ml_suggested_category
    content_tag :div, class: "flex items-center gap-2 p-2 bg-amber-50 rounded-lg border border-amber-200" do
      concat content_tag(:span, "Sugerencia:", class: "text-xs font-medium text-amber-800")
      concat content_tag(:span, suggested.name,
                        class: "inline-flex px-2 py-1 text-xs font-medium rounded-full",
                        style: "background-color: #{suggested.color}20; color: #{suggested.color};")
      concat content_tag(:div, class: "ml-auto flex gap-1") do
        concat button_to "✓",
                        accept_suggestion_expense_path(expense),
                        method: :post,
                        class: "px-2 py-1 text-xs bg-emerald-600 text-white rounded hover:bg-emerald-700",
                        title: "Aceptar sugerencia",
                        data: { turbo_frame: "expense_#{expense.id}_category" }
        concat button_to "✗",
                        reject_suggestion_expense_path(expense),
                        method: :post,
                        class: "px-2 py-1 text-xs bg-rose-600 text-white rounded hover:bg-rose-700",
                        title: "Rechazar sugerencia",
                        data: { turbo_frame: "expense_#{expense.id}_category" }
      end
    end
  end

  # Returns the learning indicator for recently corrected expenses
  def learning_indicator(expense)
    return "" unless expense.ml_last_corrected_at.present?

    if expense.ml_last_corrected_at > 1.hour.ago
      content_tag :span,
                  "📚",
                  class: "ml-1 text-xs",
                  title: "Sistema aprendiendo de esta corrección",
                  data: {
                    controller: "tooltip",
                    tooltip_content_value: "El sistema está aprendiendo de tu corrección para mejorar futuras categorizaciones"
                  }
    else
      ""
    end
  end

  # Mobile-friendly confidence display
  def mobile_confidence_display(expense)
    return "" unless expense.ml_confidence.present?

    level = expense.confidence_level
    percentage = expense.confidence_percentage

    content_tag :div, class: "flex items-center justify-between mt-2 pt-2 border-t border-slate-100" do
      left_span = content_tag(:span, "Confianza:", class: "text-xs text-slate-500")
      right_div = content_tag(:div, class: "flex items-center gap-2") do
        confidence_icon(level) + content_tag(:span, "#{percentage}%", class: "text-xs font-medium #{confidence_text_color(level)}")
      end
      left_span + right_div
    end
  end

  private

  def confidence_text_color(level)
    case level
    when :high
      "text-emerald-600"
    when :medium
      "text-teal-600"
    when :low
      "text-amber-600"
    when :very_low
      "text-rose-600"
    else
      "text-slate-500"
    end
  end
end
