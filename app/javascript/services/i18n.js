// JavaScript i18n service — reads locale from <meta name="locale"> tag
// Usage: import { t } from "services/i18n"
//        t("sync.notifications.connected")
//        t("expenses.status.pending")

const translations = {
  es: {
    sync: {
      notifications: {
        connected: "Conectado al servidor",
        disconnected: "Conexión perdida con el servidor",
        rejected: "Conexión rechazada por el servidor",
        started: "Sincronización iniciada",
        completed: "Sincronización completada: %{detected} gastos detectados de %{processed} correos",
        failed: "Error en sincronización: %{error}",
        paused: "Sincronización pausada",
        resumed: "Sincronización reanudada"
      },
      status: {
        in_progress: "Sincronización en progreso",
        paused: "Sincronización pausada",
        cache_indicator: "Datos desde caché"
      },
      actions: {
        pause: "Pausar",
        resume: "Reanudar"
      }
    },
    expenses: {
      notifications: {
        category_updated: "Categoría actualizada",
        status_updated: "Estado actualizado",
        duplicated_success: "Gasto duplicado exitosamente",
        deleted: "Gasto eliminado",
        deleted_success: "Gasto eliminado exitosamente",
        categorized_as: "Categorizado como '%{category}'"
      },
      errors: {
        category_update_failed: "Error al actualizar categoría",
        status_update_failed: "Error al actualizar estado",
        duplicate_failed: "Error al duplicar gasto",
        delete_failed: "Error al eliminar gasto",
        categorize_failed: "Error al categorizar el gasto",
        category_required: "Por favor selecciona una categoría",
        none_selected: "No hay gastos seleccionados"
      },
      status: {
        pending: "Pendiente",
        processed: "Procesado",
        failed: "Fallido",
        duplicate: "Duplicado",
        reviewed: "Revisado",
        ignored: "Ignorado",
        conflict: "Conflicto",
        uncategorized: "Sin categoría",
        categorized: "Categorizado"
      },
      confirmations: {
        delete_expense: "¿Estás seguro de eliminar este gasto?"
      }
    },
    patterns: {
      chart: {
        accuracy: "Precisión %",
        total_usage: "Uso Total",
        patterns_used: "patrones utilizados"
      },
      status: {
        accepted: "Aceptados: ",
        rejected: "Rechazados: ",
        corrected: "Corregidos: "
      },
      errors: {
        load_failed: "No se pudo cargar los datos de tendencia",
        heatmap_load_failed: "No se pudieron cargar los datos del mapa de calor",
        chart_load_failed: "No se pudo cargar los datos del gráfico",
        save_failed: "Error al guardar el patrón"
      },
      notifications: {
        saved: "Patrón guardado exitosamente",
        created: "Patrón creado",
        updated: "Patrón actualizado"
      },
      labels: {
        name: "Nombre del patrón",
        description: "Descripción del patrón",
        expected_amount: "Monto esperado",
        month: "Mes",
        week: "Semana"
      },
      categories: {
        income: "Ingresos",
        expenses: "Gastos",
        balance: "Saldo"
      },
      types: {
        regular_income: "Patrón de ingresos regulares",
        recurring_expenses: "Patrón de gastos recurrentes",
        sporadic: "Patrón de transacciones esporádicas"
      }
    },
    queue: {
      notifications: {
        connected: "Monitor de cola conectado",
        update_received: "Actualización en tiempo real de la cola recibida: "
      },
      errors: {
        http_error: "Error HTTP! estado: ",
        status_fetch: "Error al obtener estado de la cola:"
      },
      status: {
        pending: "Pendiente",
        processed: "Procesado",
        paused: "Pausado",
        just_started: "Recién iniciado",
        failed_at: "Falló el "
      },
      actions: {
        pause_all: "Pausar Todo",
        resume_all: "Reanudar Todo"
      },
      confirmations: {
        retry_all_jobs: "¿Estás seguro de que deseas reintentar todos los trabajos fallidos?"
      }
    },
    conflicts: {
      actions: {
        resolve_selected: "Resolver seleccionado(s)"
      },
      errors: {
        none_selected: "No hay conflictos seleccionados",
        resolve_failed: "conflictos no pudieron ser resueltos",
        details_load_failed: "Error al cargar los detalles del conflicto"
      },
      notifications: {
        resolved: "Conflicto resuelto exitosamente",
        resolved_success: "conflictos resueltos exitosamente"
      },
      labels: {
        select_resolution: "Seleccionar Acción de Resolución",
        merge_preview: "Vista Previa de Fusión"
      },
      confirmations: {
        resolve_method: "¿Cómo deseas resolver los conflictos seleccionados?"
      },
      resolution: {
        option_1: "Opción 1",
        option_2: "Opción 2"
      }
    },
    categories: {
      actions: {
        correct: "Corregir categoría"
      },
      labels: {
        select: "Seleccionar categoría..."
      },
      errors: {
        auto_failed: "La categorización automática falló"
      }
    },
    filters: {
      periods: {
        last_7_days: "Últimos 7 días",
        last_30_days: "Últimos 30 días",
        this_month: "Este mes",
        last_month: "Mes pasado",
        this_year: "Este año",
        last_year: "Año pasado"
      },
      labels: {
        active_filters: "Filtros activos:"
      },
      notifications: {
        restored: "Filtros restaurados",
        saved: "Filtros guardados",
        updated_from_tab: "Filtros actualizados desde otra pestaña"
      },
      suggestions: {
        apply_filter: "Sugerencia: Aplicar"
      },
      errors: {
        apply_failed: "Error al aplicar filtros. Por favor intente de nuevo."
      }
    },
    analytics: {
      metric: {
        comparison: "vs mes anterior"
      }
    },
    a11y: {
      skip_links: {
        expense_actions: "Saltar a acciones de gastos"
      },
      announcements: {
        navigated_to_actions: "Navegado a acciones de gastos",
        first_focused: "Primera acción enfocada",
        last_focused: "Última acción enfocada"
      },
      action_labels: {
        edit_category: "Editar categoría",
        update_status: "Actualizar estado",
        duplicate_expense: "Duplicar gasto",
        delete_expense: "Eliminar gasto"
      },
      labels: {
        expense: "Gasto",
        category: "Categoría",
        status: "Estado",
        date: "Fecha",
        description: "Descripción"
      },
      errors: {
        no_label: "Acción sin etiqueta"
      },
      shortcuts: {
        correct_category: "Presiona 'C' para corregir"
      }
    },
    common: {
      actions: {
        retry: "Reintentar",
        try_again: "Intentar de nuevo",
        clear: "Limpiar",
        clear_all: "Limpiar todos",
        close: "Cerrar",
        close_notification: "Cerrar notificación"
      },
      errors: {
        connection: "Error de conexión",
        try_again: "Ocurrió un error. Por favor intenta de nuevo."
      },
      status: {
        processing: "Procesando...",
        categorizing: "Categorizando...",
        updating_status: "Actualizando estado...",
        duplicating: "Duplicando gasto...",
        deleting: "Eliminando..."
      },
      labels: {
        less: "Menos",
        more: "Más",
        expanded_view: "Vista Expandida",
        compact_view: "Vista Compacta"
      },
      days: {
        sunday: "Domingo",
        monday: "Lunes",
        tuesday: "Martes",
        wednesday: "Miércoles",
        thursday: "Jueves",
        friday: "Viernes",
        saturday: "Sábado"
      },
      dates: {
        today: "Hoy",
        yesterday: "Ayer"
      }
    }
  },

  en: {
    sync: {
      notifications: {
        connected: "Connected to server",
        disconnected: "Connection lost with server",
        rejected: "Connection refused by server",
        started: "Synchronization started",
        completed: "Synchronization completed: %{detected} expenses detected from %{processed} emails",
        failed: "Synchronization error: %{error}",
        paused: "Synchronization paused",
        resumed: "Synchronization resumed"
      },
      status: {
        in_progress: "Synchronization in progress",
        paused: "Synchronization paused",
        cache_indicator: "Data from cache"
      },
      actions: {
        pause: "Pause",
        resume: "Resume"
      }
    },
    expenses: {
      notifications: {
        category_updated: "Category updated",
        status_updated: "Status updated",
        duplicated_success: "Expense duplicated successfully",
        deleted: "Expense deleted",
        deleted_success: "Expense deleted successfully",
        categorized_as: "Categorized as '%{category}'"
      },
      errors: {
        category_update_failed: "Error updating category",
        status_update_failed: "Error updating status",
        duplicate_failed: "Error duplicating expense",
        delete_failed: "Error deleting expense",
        categorize_failed: "Error categorizing expense",
        category_required: "Please select a category",
        none_selected: "No expenses selected"
      },
      status: {
        pending: "Pending",
        processed: "Processed",
        failed: "Failed",
        duplicate: "Duplicate",
        reviewed: "Reviewed",
        ignored: "Ignored",
        conflict: "Conflict",
        uncategorized: "Uncategorized",
        categorized: "Categorized"
      },
      confirmations: {
        delete_expense: "Are you sure you want to delete this expense?"
      }
    },
    patterns: {
      chart: {
        accuracy: "Accuracy %",
        total_usage: "Total Usage",
        patterns_used: "patterns used"
      },
      status: {
        accepted: "Accepted: ",
        rejected: "Rejected: ",
        corrected: "Corrected: "
      },
      errors: {
        load_failed: "Could not load trend data",
        heatmap_load_failed: "Could not load heatmap data",
        chart_load_failed: "Could not load chart data",
        save_failed: "Error saving pattern"
      },
      notifications: {
        saved: "Pattern saved successfully",
        created: "Pattern created",
        updated: "Pattern updated"
      },
      labels: {
        name: "Pattern name",
        description: "Pattern description",
        expected_amount: "Expected amount",
        month: "Month",
        week: "Week"
      },
      categories: {
        income: "Income",
        expenses: "Expenses",
        balance: "Balance"
      },
      types: {
        regular_income: "Regular income pattern",
        recurring_expenses: "Recurring expense pattern",
        sporadic: "Sporadic transaction pattern"
      }
    },
    queue: {
      notifications: {
        connected: "Queue monitor connected",
        update_received: "Real-time queue update received: "
      },
      errors: {
        http_error: "HTTP error! status: ",
        status_fetch: "Error getting queue status:"
      },
      status: {
        pending: "Pending",
        processed: "Processed",
        paused: "Paused",
        just_started: "Just started",
        failed_at: "Failed at "
      },
      actions: {
        pause_all: "Pause All",
        resume_all: "Resume All"
      },
      confirmations: {
        retry_all_jobs: "Are you sure you want to retry all failed jobs?"
      }
    },
    conflicts: {
      actions: {
        resolve_selected: "Resolve selected"
      },
      errors: {
        none_selected: "No conflicts selected",
        resolve_failed: "conflicts could not be resolved",
        details_load_failed: "Error loading conflict details"
      },
      notifications: {
        resolved: "Conflict resolved successfully",
        resolved_success: "conflicts resolved successfully"
      },
      labels: {
        select_resolution: "Select Resolution Action",
        merge_preview: "Merge Preview"
      },
      confirmations: {
        resolve_method: "How do you want to resolve the selected conflicts?"
      },
      resolution: {
        option_1: "Option 1",
        option_2: "Option 2"
      }
    },
    categories: {
      actions: {
        correct: "Correct category"
      },
      labels: {
        select: "Select category..."
      },
      errors: {
        auto_failed: "Auto-categorization failed"
      }
    },
    filters: {
      periods: {
        last_7_days: "Last 7 days",
        last_30_days: "Last 30 days",
        this_month: "This month",
        last_month: "Last month",
        this_year: "This year",
        last_year: "Last year"
      },
      labels: {
        active_filters: "Active filters:"
      },
      notifications: {
        restored: "Filters restored",
        saved: "Filters saved",
        updated_from_tab: "Filters updated from another tab"
      },
      suggestions: {
        apply_filter: "Suggestion: Apply"
      },
      errors: {
        apply_failed: "Error applying filters. Please try again."
      }
    },
    analytics: {
      metric: {
        comparison: "vs previous month"
      }
    },
    a11y: {
      skip_links: {
        expense_actions: "Skip to expense actions"
      },
      announcements: {
        navigated_to_actions: "Navigated to expense actions",
        first_focused: "First action focused",
        last_focused: "Last action focused"
      },
      action_labels: {
        edit_category: "Edit category",
        update_status: "Update status",
        duplicate_expense: "Duplicate expense",
        delete_expense: "Delete expense"
      },
      labels: {
        expense: "Expense",
        category: "Category",
        status: "Status",
        date: "Date",
        description: "Description"
      },
      errors: {
        no_label: "Action without label"
      },
      shortcuts: {
        correct_category: "Press 'C' to correct"
      }
    },
    common: {
      actions: {
        retry: "Retry",
        try_again: "Try again",
        clear: "Clear",
        clear_all: "Clear all",
        close: "Close",
        close_notification: "Close notification"
      },
      errors: {
        connection: "Connection error",
        try_again: "An error occurred. Please try again."
      },
      status: {
        processing: "Processing...",
        categorizing: "Categorizing...",
        updating_status: "Updating status...",
        duplicating: "Duplicating expense...",
        deleting: "Deleting..."
      },
      labels: {
        less: "Less",
        more: "More",
        expanded_view: "Expanded View",
        compact_view: "Compact View"
      },
      days: {
        sunday: "Sunday",
        monday: "Monday",
        tuesday: "Tuesday",
        wednesday: "Wednesday",
        thursday: "Thursday",
        friday: "Friday",
        saturday: "Saturday"
      },
      dates: {
        today: "Today",
        yesterday: "Yesterday"
      }
    }
  }
}

function getLocale() {
  const meta = document.querySelector('meta[name="locale"]')
  return meta?.content || 'es'
}

function getNestedValue(obj, path) {
  return path.split('.').reduce((current, key) => current?.[key], obj)
}

/**
 * Translate a key to the current locale.
 * Supports interpolation: t("key", { name: "value" })
 * @param {string} key - Dot-separated translation key
 * @param {Object} [params] - Interpolation values
 * @returns {string} Translated string or the key if not found
 */
export function t(key, params = {}) {
  const locale = getLocale()
  const value = getNestedValue(translations[locale], key)
    || getNestedValue(translations.es, key) // fallback to Spanish
    || key // fallback to key itself

  if (typeof value !== 'string') return key

  // Interpolate %{variable} patterns
  return value.replace(/%\{(\w+)\}/g, (_, name) => params[name] ?? `%{${name}}`)
}

export default { t }
