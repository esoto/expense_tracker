# frozen_string_literal: true

module PatternsHelper
  PATTERN_TYPE_TRANSLATIONS = {
    "merchant" => "Comercio",
    "keyword" => "Palabra clave",
    "description" => "Descripción",
    "amount_range" => "Rango de monto",
    "regex" => "Regex",
    "time" => "Hora"
  }.freeze

  def pattern_type_badge(type)
    colors = {
      "merchant" => "slate",
      "keyword" => "amber",
      "description" => "teal",
      "amount_range" => "emerald",
      "regex" => "rose",
      "time" => "indigo"
    }

    color = colors[type] || "slate"
    label = PATTERN_TYPE_TRANSLATIONS[type] || type.humanize

    content_tag :span, label,
                class: "px-2 py-1 text-xs rounded-full bg-#{color}-100 text-#{color}-700"
  end

  def success_rate_bar(rate, size: "normal")
    width_class = size == "small" ? "w-12" : "w-16"
    height_class = size == "small" ? "h-1.5" : "h-2"

    color = if rate >= 0.7
              "emerald"
    elsif rate >= 0.4
              "amber"
    else
              "rose"
    end

    content_tag :div, class: "flex items-center" do
      content_tag(:div, class: "#{width_class} bg-slate-200 rounded-full #{height_class} mr-2") do
        content_tag(:div, "",
                   class: "bg-#{color}-500 #{height_class} rounded-full",
                   style: "width: #{(rate * 100).round}%")
      end +
      content_tag(:span, "#{(rate * 100).round}%",
                 class: size == "small" ? "text-xs text-slate-700" : "text-slate-700")
    end
  end

  def confidence_badge(weight)
    color = if weight >= 2
              "teal"
    elsif weight >= 1
              "slate"
    else
              "amber"
    end

    content_tag :span, weight.round(1),
                class: "px-2 py-1 text-xs rounded-full bg-#{color}-100 text-#{color}-700"
  end

  def pattern_status_badge(pattern)
    if pattern.active?
      content_tag :span, "Activo",
                  class: "px-2 py-1 text-xs rounded-full bg-emerald-100 text-emerald-700"
    else
      content_tag :span, "Inactivo",
                  class: "px-2 py-1 text-xs rounded-full bg-slate-100 text-slate-500"
    end
  end

  def pattern_source_badge(pattern)
    if pattern.user_created?
      content_tag :span, "Creado por usuario",
                  class: "px-2 py-1 text-xs rounded-full bg-amber-100 text-amber-700"
    else
      content_tag :span, "Sistema",
                  class: "px-2 py-1 text-xs rounded-full bg-slate-100 text-slate-700"
    end
  end

  def category_badge(category)
    content_tag :span, category.name,
                class: "px-2 py-1 text-xs rounded-full bg-teal-100 text-teal-700"
  end

  def operator_badge(operator)
    colors = {
      "AND" => "amber",
      "OR" => "teal",
      "NOT" => "rose"
    }

    color = colors[operator] || "slate"

    content_tag :span, operator,
                class: "px-2 py-1 text-xs rounded-full bg-#{color}-100 text-#{color}-700"
  end

  def pattern_type_options
    [
      [ "Nombre de comercio", "merchant" ],
      [ "Palabra clave", "keyword" ],
      [ "Descripción", "description" ],
      [ "Rango de monto", "amount_range" ],
      [ "Expresión regular", "regex" ],
      [ "Patrón de hora", "time" ]
    ]
  end

  def pattern_type_filter_options
    [
      [ "Todos los tipos", "" ],
      [ "Comercio", "merchant" ],
      [ "Palabra clave", "keyword" ],
      [ "Descripción", "description" ],
      [ "Rango de monto", "amount_range" ],
      [ "Regex", "regex" ],
      [ "Hora", "time" ]
    ]
  end

  def pattern_status_filter_options
    [
      [ "Todos los estados", "" ],
      [ "Activo", "active" ],
      [ "Inactivo", "inactive" ],
      [ "Creado por usuario", "user_created" ],
      [ "Creado por sistema", "system_created" ],
      [ "Alta confianza", "high_confidence" ],
      [ "Exitoso", "successful" ],
      [ "Uso frecuente", "frequently_used" ]
    ]
  end
end
