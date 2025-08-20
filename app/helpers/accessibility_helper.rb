# Accessibility Helper for WCAG 2.1 AA Compliance
# Task 3.9: Dashboard Accessibility
module AccessibilityHelper
  # Color contrast ratios for WCAG 2.1 AA compliance
  WCAG_AA_NORMAL_RATIO = 4.5   # For normal text (14pt/18.66px or smaller)
  WCAG_AA_LARGE_RATIO = 3.0    # For large text (18pt/24px or 14pt/18.66px bold)

  # Generate ARIA labels for expense items
  def expense_aria_label(expense, index = nil)
    parts = []
    parts << "Gasto #{index}" if index
    parts << (expense.merchant_name || "Comercio desconocido")
    parts << "#{currency_symbol(expense)}#{number_with_delimiter(expense.amount.to_i)}"
    parts << expense.transaction_date.strftime("%d de %B de %Y")
    parts << "Categoría: #{expense.category&.name || 'Sin categoría'}"
    parts << "Estado: #{expense.status == 'pending' ? 'Pendiente' : 'Procesado'}"

    parts.join(", ")
  end

  # Generate accessible button labels
  def accessible_button_label(action, expense = nil, context = nil)
    case action
    when "categorize"
      expense ? "Cambiar categoría del gasto de #{expense.merchant_name}" : "Categorizar gasto"
    when "status"
      if expense
        status_action = expense.status == "pending" ? "Marcar como procesado" : "Marcar como pendiente"
        "#{status_action} el gasto de #{expense.merchant_name}"
      else
        "Cambiar estado del gasto"
      end
    when "duplicate"
      expense ? "Duplicar gasto de #{expense.merchant_name}" : "Duplicar gasto"
    when "delete"
      expense ? "Eliminar gasto de #{expense.merchant_name}" : "Eliminar gasto"
    when "select"
      expense ? "Seleccionar gasto: #{expense.merchant_name}, #{currency_symbol(expense)}#{number_with_delimiter(expense.amount.to_i)}" : "Seleccionar gasto"
    when "select_all"
      count = context || 0
      "Seleccionar todos los #{count} gastos visibles"
    when "bulk_categorize"
      count = context || 0
      "Categorizar #{count} gastos seleccionados"
    when "bulk_status"
      count = context || 0
      "Cambiar estado de #{count} gastos seleccionados"
    when "bulk_delete"
      count = context || 0
      "Eliminar #{count} gastos seleccionados (acción irreversible)"
    else
      action.humanize
    end
  end

  # Generate skip link content
  def skip_links
    content_tag :div, class: "sr-only-focusable" do
      [
        link_to("Saltar al contenido principal", "#main-content", class: "skip-link"),
        link_to("Saltar a la navegación", "#main-navigation", class: "skip-link"),
        link_to("Saltar a los filtros", "#filter-chips-title", class: "skip-link"),
        link_to("Saltar a la lista de gastos", "#recent-expenses-title", class: "skip-link")
      ].join.html_safe
    end
  end

  # Generate live region announcements
  def announce_to_screen_reader(message, level = :polite)
    target_id = level == :assertive ? "accessibility-alerts" : "accessibility-status"

    content_tag :script, type: "text/javascript" do
      raw "
        (function() {
          const region = document.getElementById('#{target_id}');
          if (region) {
            region.textContent = '#{j(message)}';
            setTimeout(() => region.textContent = '', 5000);
          }
        })();
      "
    end
  end

  # Generate ARIA descriptions for complex UI
  def dashboard_help_text
    content_tag :div, class: "sr-only" do
      [
        content_tag(:div, "Dashboard de gastos. Use Tab para navegar entre elementos o las teclas de acceso rápido:", id: "dashboard-help"),
        content_tag(:div, "Alt+1: Filtros rápidos", id: "filters-help"),
        content_tag(:div, "Alt+2: Lista de gastos", id: "expenses-help"),
        content_tag(:div, "Alt+3: Acciones de selección", id: "selection-help"),
        content_tag(:div, "Escape: Limpiar filtros o salir de modales", id: "escape-help"),
        content_tag(:div, "Ctrl+Shift+S: Activar selección múltiple", id: "selection-mode-help"),
        content_tag(:div, "Ctrl+Shift+V: Cambiar vista", id: "view-mode-help")
      ].join.html_safe
    end
  end

  # Check color contrast programmatically
  def verify_color_contrast(foreground, background)
    fg_rgb = hex_to_rgb(foreground)
    bg_rgb = hex_to_rgb(background)

    fg_luminance = relative_luminance(fg_rgb)
    bg_luminance = relative_luminance(bg_rgb)

    # Ensure light color is numerator
    light = [ fg_luminance, bg_luminance ].max
    dark = [ fg_luminance, bg_luminance ].min

    contrast_ratio = (light + 0.05) / (dark + 0.05)

    {
      ratio: contrast_ratio.round(2),
      aa_normal: contrast_ratio >= WCAG_AA_NORMAL_RATIO,
      aa_large: contrast_ratio >= WCAG_AA_LARGE_RATIO,
      foreground: foreground,
      background: background
    }
  end

  # Generate accessible table headers
  def accessible_table_headers(columns)
    headers = columns.map do |column|
      content_tag :th,
        column[:label],
        scope: "col",
        id: "header-#{column[:key]}",
        class: column[:class] || "px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider"
    end

    content_tag :thead, class: "bg-slate-50" do
      content_tag :tr do
        headers.join.html_safe
      end
    end
  end

  # Generate accessible form labels with required indicators
  def accessible_label(form, field, text, options = {})
    required = options.delete(:required)
    help_text = options.delete(:help)

    label_text = text
    label_text += content_tag(:span, " *", class: "text-rose-600", "aria-label": "obligatorio") if required

    label_html = form.label field, label_text.html_safe, options

    if help_text
      help_id = "#{field}_help"
      help_html = content_tag :div, help_text, id: help_id, class: "text-sm text-slate-600 mt-1"
      label_html + help_html
    else
      label_html
    end
  end

  # Generate keyboard shortcut indicators
  def keyboard_shortcuts_help
    shortcuts = [
      { key: "Tab", description: "Navegar entre elementos" },
      { key: "Shift+Tab", description: "Navegar hacia atrás" },
      { key: "Enter/Space", description: "Activar botón o enlace" },
      { key: "Escape", description: "Cerrar modal o limpiar filtros" },
      { key: "↑↓", description: "Navegar en listas" },
      { key: "Alt+1", description: "Ir a filtros" },
      { key: "Alt+2", description: "Ir a lista de gastos" },
      { key: "Ctrl+Shift+S", description: "Activar selección múltiple" },
      { key: "Ctrl+Shift+V", description: "Cambiar vista" }
    ]

    content_tag :div, class: "sr-only", id: "keyboard-shortcuts" do
      content_tag(:h3, "Atajos de teclado disponibles:") +
      content_tag(:ul) do
        shortcuts.map do |shortcut|
          content_tag :li, "#{shortcut[:key]}: #{shortcut[:description]}"
        end.join.html_safe
      end
    end
  end

  # Generate focus management utilities
  def focus_trap_script(modal_id)
    javascript_tag do
      raw "
        (function() {
          const modal = document.getElementById('#{modal_id}');
          if (!modal) return;

          const focusableElements = modal.querySelectorAll(
            'button, [href], input, select, textarea, [tabindex]:not([tabindex=\"-1\"])'
          );

          if (focusableElements.length === 0) return;

          const firstElement = focusableElements[0];
          const lastElement = focusableElements[focusableElements.length - 1];

          modal.addEventListener('keydown', function(e) {
            if (e.key === 'Tab') {
              if (e.shiftKey) {
                if (document.activeElement === firstElement) {
                  e.preventDefault();
                  lastElement.focus();
                }
              } else {
                if (document.activeElement === lastElement) {
                  e.preventDefault();
                  firstElement.focus();
                }
              }
            }

            if (e.key === 'Escape') {
              modal.querySelector('[data-dismiss]')?.click();
            }
          });

          // Focus first element when modal opens
          setTimeout(() => firstElement.focus(), 100);
        })();
      "
    end
  end

  private

  def hex_to_rgb(hex)
    hex = hex.gsub("#", "")
    {
      r: hex[0..1].to_i(16) / 255.0,
      g: hex[2..3].to_i(16) / 255.0,
      b: hex[4..5].to_i(16) / 255.0
    }
  end

  def relative_luminance(rgb)
    # Convert RGB to relative luminance using WCAG formula
    r = rgb[:r] <= 0.03928 ? rgb[:r] / 12.92 : ((rgb[:r] + 0.055) / 1.055) ** 2.4
    g = rgb[:g] <= 0.03928 ? rgb[:g] / 12.92 : ((rgb[:g] + 0.055) / 1.055) ** 2.4
    b = rgb[:b] <= 0.03928 ? rgb[:b] / 12.92 : ((rgb[:b] + 0.055) / 1.055) ** 2.4

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
