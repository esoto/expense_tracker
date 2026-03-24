module ApplicationHelper
  def currency_symbol(expense)
    return "₡" if expense.crc?
    return "$" if expense.usd?
    return "€" if expense.eur?
    "₡" # Default fallback
  end

  def format_datetime(datetime)
    return "N/A" if datetime.blank?
    datetime.strftime("%B %d, %Y at %I:%M %p")
  end

  def format_date(date)
    return "N/A" if date.blank?
    date.strftime("%B %d, %Y")
  end

  def flash_css_class(type)
    case type.to_sym
    when :notice, :success
      "bg-emerald-50 border border-emerald-200 text-emerald-700"
    when :alert, :error
      "bg-rose-50 border border-rose-200 text-rose-700"
    when :warning
      "bg-amber-50 border border-amber-200 text-amber-700"
    else
      "bg-slate-50 border border-slate-200 text-slate-700"
    end
  end

  # Render pagination controls styled with the Financial Confidence color palette.
  # Uses teal-700 for active/primary states and slate for text/borders (never blue).
  # Preserves existing query parameters (filters, sort, etc.) when navigating pages.
  def pagy_financial_nav(pagy_obj)
    return "".html_safe if pagy_obj.pages <= 1

    link_classes = "px-3 py-2 text-sm font-medium text-slate-700 bg-white border border-slate-200 " \
                   "rounded-lg hover:bg-teal-50 hover:text-teal-700 hover:border-teal-300 transition-colors"

    html = +""
    html << '<nav aria-label="Paginación" class="flex items-center justify-center gap-1">'

    # Previous button
    if pagy_obj.previous
      html << pagination_link("« Anterior", pagy_obj.previous, link_classes)
    else
      html << pagination_disabled_span("« Anterior")
    end

    # Page number links
    build_page_series(pagy_obj).each do |item|
      case item
      when :gap
        html << '<span class="px-2 py-2 text-sm text-slate-500">...</span>'
      when pagy_obj.page
        html << pagination_active_span(item)
      else
        html << pagination_link(item.to_s, item, link_classes)
      end
    end

    # Next button
    if pagy_obj.next
      html << pagination_link("Siguiente »", pagy_obj.next, link_classes)
    else
      html << pagination_disabled_span("Siguiente »")
    end

    html << "</nav>"
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  # Build a page series array for rendering pagination links.
  # Returns an array of page numbers and :gap symbols.
  # Example: [1, 2, 3, :gap, 8, 9, 10, :gap, 18, 19, 20]
  def build_page_series(pagy_obj)
    total = pagy_obj.pages
    current = pagy_obj.page

    return (1..total).to_a if total <= 9

    series = []
    # Always show first page
    series << 1

    # Calculate range around current page
    left = [ current - 2, 2 ].max
    right = [ current + 2, total - 1 ].min

    series << :gap if left > 2
    (left..right).each { |p| series << p }
    series << :gap if right < total - 1

    # Always show last page
    series << total unless series.include?(total)

    series
  end

  def pagination_page_url(page_number)
    # Merge the page param with existing query parameters to preserve filters
    query_params = request.query_parameters.merge("page" => page_number)
    "#{request.path}?#{query_params.to_query}"
  end

  def pagination_link(text, page_number, css_class)
    url = pagination_page_url(page_number)
    tag.a(
      text,
      href: url,
      class: css_class,
      "aria-label": "Ir a página #{page_number}"
    )
  end

  def pagination_active_span(page_number)
    %(<span class="px-3 py-2 text-sm font-semibold text-white bg-teal-700 rounded-lg" aria-current="page">#{page_number}</span>)
  end

  def pagination_disabled_span(text)
    %(<span class="px-3 py-2 text-sm text-slate-400 cursor-not-allowed">#{text}</span>)
  end
end
