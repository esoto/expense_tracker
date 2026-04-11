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
    sync_sessions: {
      progress: "Progreso",
      expenses_label: "gastos",
      processing: "Procesando"
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
        delete_bulk_failed: "Error al eliminar gastos",
        categorize_failed: "Error al categorizar el gasto",
        categorize_bulk_failed: "Error al categorizar gastos",
        status_bulk_failed: "Error al actualizar estado",
        category_required: "Por favor selecciona una categoría",
        none_selected: "No hay gastos seleccionados",
        select_one: "Por favor selecciona al menos un gasto",
        select_status: "Por favor selecciona un estado",
        load_categories: "Error al cargar categorías",
        load_more: "Error al cargar más gastos"
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
        categorized: "Categorizado",
        requires_review: "Requiere revisión",
        fully_reviewed: "Completamente revisado"
      },
      confirmations: {
        delete_expense: "¿Estás seguro de eliminar este gasto?",
        delete_single: "¿Estás seguro de que quieres eliminar este gasto?"
      },
      labels: {
        load_more: "Cargar más gastos",
        load_more_error: "Error - Intentar de nuevo",
        uncategorized: "Sin categoría",
        select_category: "Seleccionar categoría...",
        position_restored: "Posición restaurada"
      },
      bulk: {
        confirm_delete_title: "Confirmar Eliminación",
        categorize_title: "Categorizar Gastos",
        status_title: "Actualizar Estado",
        apply_category: "Aplicar Categoría",
        update_status: "Actualizar Estado",
        cancel: "Cancelar",
        delete_confirm_body: "¿Estás seguro de que quieres eliminar",
        delete_expense_singular: "gasto",
        delete_expense_plural: "gastos",
        delete_undo_note: "Los gastos se eliminarán pero podrás deshacer esta acción durante los próximos 30 segundos.",
        select_category_for: "Selecciona una categoría para aplicar a",
        category_label: "Categoría",
        category_note: "Esta acción actualizará la categoría de todos los gastos seleccionados y registrará la corrección para mejorar las sugerencias futuras del sistema."
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
      },
      confirmations: {
        delete_selected: "¿Estás seguro de que deseas eliminar los patrones seleccionados?"
      },
      form: {
        help: {
          merchant: "Ingresa el nombre del comerciante para hacer coincidir (sin distinción de mayúsculas)",
          keyword: "Ingresa una palabra clave para buscar en descripciones y nombres de comerciantes",
          description: "Ingresa texto para hacer coincidir en descripciones de gastos",
          amount_range: "Ingresa el rango como: mín-máx (por ejemplo, 10.00-50.00)",
          regex: "Ingresa un patrón de expresión regular",
          time: "Ingresa: mañana, tarde, noche, fin de semana, entre semana o rango de horas (09:00-17:00)",
          default: "Selecciona un tipo de patrón para ver la ayuda del formato de valor"
        },
        placeholders: {
          merchant: "ej., Starbucks",
          keyword: "ej., café",
          description: "ej., Suscripción mensual",
          amount_range: "ej., 10.00-50.00",
          regex: "ej., ^UBER.*",
          time: "ej., mañana o 09:00-17:00",
          default: "Ingresa el valor del patrón..."
        },
        validation: {
          fill_required: "Por favor ingresa todos los campos requeridos"
        },
        test: {
          match: "¡El patrón coincide!",
          no_match: "Sin coincidencia"
        }
      }
    },
    queue: {
      notifications: {
        connected: "Monitor de cola conectado",
        update_received: "Actualización en tiempo real de la cola recibida: ",
        job_queued_retry: "Trabajo %{jobId} encolado para reintentar",
        job_cleared: "Trabajo %{jobId} limpiado"
      },
      errors: {
        http_error: "Error HTTP! estado: ",
        status_fetch: "Error al obtener estado de la cola:",
        load_status: "Error al cargar estado de la cola",
        toggle_pause: "Error al cambiar pausa de la cola",
        retry_job: "Error al reintentar trabajo",
        clear_job: "Error al limpiar trabajo",
        retry_all: "Error al reintentar todos los trabajos fallidos",
        clear_all_not_implemented: "Limpiar todo aún no está implementado",
        unknown_error: "Error desconocido",
        operation_failed: "Operación fallida",
        retry_all_failed: "Error al reintentar trabajos"
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
        retry_all_jobs: "¿Estás seguro de que deseas reintentar todos los trabajos fallidos?",
        clear_all_jobs: "¿Estás seguro de que deseas limpiar todos los trabajos fallidos? Esta acción no se puede deshacer."
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
        correct: "Corregir categoría",
        apply: "Aplicar",
        cancel: "Cancelar"
      },
      labels: {
        select: "Seleccionar categoría..."
      },
      errors: {
        auto_failed: "La categorización automática falló"
      },
      confidence: {
        display: "Confianza: %{percentage}%",
        very_high: "Confianza muy alta - categorización altamente precisa",
        high: "Alta probabilidad de categorización correcta",
        medium: "Categorización probable pero puede requerir revisión",
        low: "Baja confianza - se recomienda revisar",
        very_low: "Muy baja confianza - requiere revisión manual",
        shortcut_hint: "Presiona 'C' para corregir"
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
        apply_filter: "Sugerencia: Aplicar",
        frequent_categories: "categorías frecuentes",
        period: "período"
      },
      errors: {
        apply_failed: "Error al aplicar filtros. Por favor intente de nuevo."
      },
      confirmations: {
        reset_all: "¿Estás seguro de que quieres restablecer todos los filtros y preferencias?"
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
        last_focused: "Última acción enfocada",
        modal_opened: "Modal abierto",
        modal_closed: "Modal cerrado",
        menus_closed: "Menús cerrados",
        selection_cleared: "Selección limpiada",
        page_loaded: "Página cargada. Use Tab para navegar o presione Alt+H para ayuda con atajos de teclado.",
        filters_focused: "Enfocado en filtros rápidos",
        expense_list_focused: "Enfocado en lista de gastos",
        selection_focused: "Enfocado en acciones de selección",
        selection_mode_inactive: "Modo de selección no activo",
        shortcuts_opened: "Ayuda de atajos de teclado abierta",
        shortcuts_closed: "Ayuda de atajos cerrada",
        high_contrast_enabled: "Modo de alto contraste activado",
        high_contrast_disabled: "Modo de alto contraste desactivado",
        selection_mode_enabled: "Modo de selección activado. Usa la barra espaciadora para seleccionar elementos.",
        selection_mode_disabled: "Modo de selección desactivado",
        no_items_selected: "Ningún elemento seleccionado",
        expanded_view_unavailable: "Vista expandida no disponible en dispositivos móviles"
      },
      action_labels: {
        edit_category: "Editar categoría",
        update_status: "Actualizar estado",
        duplicate_expense: "Duplicar gasto",
        delete_expense: "Eliminar gasto",
        edit_expense: "Editar gasto",
        change_status: "Cambiar estado",
        change_category: "Cambiar categoría",
        unlabeled_action: "Acción"
      },
      labels: {
        expense: "Gasto",
        category: "Categoría",
        status: "Estado",
        date: "Fecha",
        description: "Descripción",
        expense_list: "Lista de gastos"
      },
      errors: {
        no_label: "Acción sin etiqueta"
      },
      shortcuts: {
        correct_category: "Presiona 'C' para corregir",
        title: "Atajos de Teclado",
        close_help: "Cerrar ayuda",
        close_help_shortcuts: "Cerrar ayuda de atajos",
        close_button: "Cerrar",
        tab_navigate: "Tab/Shift+Tab: Navegar entre elementos",
        enter_activate: "Enter/Espacio: Activar botón o enlace",
        escape_close: "Escape: Cerrar modales o limpiar filtros",
        arrows_navigate: "Flechas: Navegar en listas y filtros",
        alt1_filters: "Alt+1: Ir a filtros rápidos",
        alt2_list: "Alt+2: Ir a lista de gastos",
        alt3_selection: "Alt+3: Ir a acciones de selección",
        ctrl_shift_s: "Ctrl+Shift+S: Activar selección múltiple",
        ctrl_shift_v: "Ctrl+Shift+V: Cambiar vista",
        c_categorize: "C: Categorizar (en lista de gastos)",
        s_status: "S: Cambiar estado (en lista de gastos)",
        d_duplicate: "D: Duplicar (en lista de gastos)",
        del_delete: "Del: Eliminar (en lista de gastos)",
        press_enter_edit: "Presiona Enter para editar este gasto",
        press_enter_delete: "Presiona Enter para eliminar este gasto. Podrás restaurarlo desde el historial.",
        press_enter_duplicate: "Presiona Enter para crear una copia de este gasto",
        press_enter_status: "Presiona Enter para cambiar el estado del gasto",
        press_enter_category: "Presiona Enter para cambiar la categoría del gasto",
        press_enter_execute: "Presiona Enter para ejecutar esta acción"
      }
    },
    bulk_operations: {
      operations: {
        categorize: "Categorizar Gastos",
        status: "Actualizar Estado",
        delete: "Eliminar Gastos",
        execute: "Ejecutar"
      },
      notifications: {
        completed: "Operación completada exitosamente"
      },
      errors: {
        connection: "Error de conexión. Por favor, intenta nuevamente.",
        no_operation_selected: "Por favor selecciona un tipo de operación",
        no_category_selected: "Por favor selecciona una categoría",
        no_status_selected: "Por favor selecciona un estado",
        confirm_deletion: "Por favor confirma la eliminación",
        invalid_operation: "Operación no válida",
        processing_error: "Ocurrió un error al procesar la operación"
      },
      progress: {
        processing: "Procesando %{count} gastos..."
      },
      partial_errors: {
        items_failed: "%{count} gastos no pudieron ser procesados",
        expense_item: "Gasto #%{id}: %{error}",
        more_items: "... y %{count} más"
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
    sync_sessions: {
      progress: "Progress",
      expenses_label: "expenses",
      processing: "Processing"
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
        delete_bulk_failed: "Error deleting expenses",
        categorize_failed: "Error categorizing expense",
        categorize_bulk_failed: "Error categorizing expenses",
        status_bulk_failed: "Error updating status",
        category_required: "Please select a category",
        none_selected: "No expenses selected",
        select_one: "Please select at least one expense",
        select_status: "Please select a status",
        load_categories: "Error loading categories",
        load_more: "Error loading more expenses"
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
        categorized: "Categorized",
        requires_review: "Requires review",
        fully_reviewed: "Fully reviewed"
      },
      confirmations: {
        delete_expense: "Are you sure you want to delete this expense?",
        delete_single: "Are you sure you want to delete this expense?"
      },
      labels: {
        load_more: "Load more expenses",
        load_more_error: "Error - Try again",
        uncategorized: "Uncategorized",
        select_category: "Select category...",
        position_restored: "Position restored"
      },
      bulk: {
        confirm_delete_title: "Confirm Deletion",
        categorize_title: "Categorize Expenses",
        status_title: "Update Status",
        apply_category: "Apply Category",
        update_status: "Update Status",
        cancel: "Cancel",
        delete_confirm_body: "Are you sure you want to delete",
        delete_expense_singular: "expense",
        delete_expense_plural: "expenses",
        delete_undo_note: "Expenses will be deleted but you can undo this action for the next 30 seconds.",
        select_category_for: "Select a category to apply to",
        category_label: "Category",
        category_note: "This action will update the category of all selected expenses and will record the correction to improve future system suggestions."
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
      },
      confirmations: {
        delete_selected: "Are you sure you want to delete the selected patterns?"
      },
      form: {
        help: {
          merchant: "Enter the merchant name to match (case-insensitive)",
          keyword: "Enter a keyword to search in descriptions and merchant names",
          description: "Enter text to match in expense descriptions",
          amount_range: "Enter the range as: min-max (e.g., 10.00-50.00)",
          regex: "Enter a regular expression pattern",
          time: "Enter: morning, afternoon, evening, weekend, weekday or time range (09:00-17:00)",
          default: "Select a pattern type to see value format help"
        },
        placeholders: {
          merchant: "e.g., Starbucks",
          keyword: "e.g., coffee",
          description: "e.g., Monthly subscription",
          amount_range: "e.g., 10.00-50.00",
          regex: "e.g., ^UBER.*",
          time: "e.g., morning or 09:00-17:00",
          default: "Enter the pattern value..."
        },
        validation: {
          fill_required: "Please fill in all required fields"
        },
        test: {
          match: "Pattern matches!",
          no_match: "No match"
        }
      }
    },
    queue: {
      notifications: {
        connected: "Queue monitor connected",
        update_received: "Real-time queue update received: ",
        job_queued_retry: "Job %{jobId} queued for retry",
        job_cleared: "Job %{jobId} cleared"
      },
      errors: {
        http_error: "HTTP error! status: ",
        status_fetch: "Error getting queue status:",
        load_status: "Error loading queue status",
        toggle_pause: "Error toggling queue pause",
        retry_job: "Error retrying job",
        clear_job: "Error clearing job",
        retry_all: "Error retrying all failed jobs",
        clear_all_not_implemented: "Clear all is not yet implemented",
        unknown_error: "Unknown error",
        operation_failed: "Operation failed",
        retry_all_failed: "Error retrying jobs"
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
        retry_all_jobs: "Are you sure you want to retry all failed jobs?",
        clear_all_jobs: "Are you sure you want to clear all failed jobs? This action cannot be undone."
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
        correct: "Correct category",
        apply: "Apply",
        cancel: "Cancel"
      },
      labels: {
        select: "Select category..."
      },
      errors: {
        auto_failed: "Auto-categorization failed"
      },
      confidence: {
        display: "Confidence: %{percentage}%",
        very_high: "Very high confidence - highly accurate categorization",
        high: "High probability of correct categorization",
        medium: "Probable categorization but may require review",
        low: "Low confidence - recommended to review",
        very_low: "Very low confidence - requires manual review",
        shortcut_hint: "Press 'C' to correct"
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
        apply_filter: "Suggestion: Apply",
        frequent_categories: "frequent categories",
        period: "period"
      },
      errors: {
        apply_failed: "Error applying filters. Please try again."
      },
      confirmations: {
        reset_all: "Are you sure you want to reset all filters and preferences?"
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
        last_focused: "Last action focused",
        modal_opened: "Modal opened",
        modal_closed: "Modal closed",
        menus_closed: "Menus closed",
        selection_cleared: "Selection cleared",
        page_loaded: "Page loaded. Use Tab to navigate or press Alt+H for keyboard shortcuts help.",
        filters_focused: "Focused on quick filters",
        expense_list_focused: "Focused on expense list",
        selection_focused: "Focused on selection actions",
        selection_mode_inactive: "Selection mode not active",
        shortcuts_opened: "Keyboard shortcuts help opened",
        shortcuts_closed: "Shortcuts help closed",
        high_contrast_enabled: "High contrast mode enabled",
        high_contrast_disabled: "High contrast mode disabled",
        selection_mode_enabled: "Selection mode enabled. Use spacebar to select items.",
        selection_mode_disabled: "Selection mode disabled",
        no_items_selected: "No items selected",
        expanded_view_unavailable: "Expanded view not available on mobile devices"
      },
      action_labels: {
        edit_category: "Edit category",
        update_status: "Update status",
        duplicate_expense: "Duplicate expense",
        delete_expense: "Delete expense",
        edit_expense: "Edit expense",
        change_status: "Change status",
        change_category: "Change category",
        unlabeled_action: "Action"
      },
      labels: {
        expense: "Expense",
        category: "Category",
        status: "Status",
        date: "Date",
        description: "Description",
        expense_list: "Expense list"
      },
      errors: {
        no_label: "Action without label"
      },
      shortcuts: {
        correct_category: "Press 'C' to correct",
        title: "Keyboard Shortcuts",
        close_help: "Close help",
        close_help_shortcuts: "Close shortcuts help",
        close_button: "Close",
        tab_navigate: "Tab/Shift+Tab: Navigate between elements",
        enter_activate: "Enter/Space: Activate button or link",
        escape_close: "Escape: Close modals or clear filters",
        arrows_navigate: "Arrows: Navigate in lists and filters",
        alt1_filters: "Alt+1: Go to quick filters",
        alt2_list: "Alt+2: Go to expense list",
        alt3_selection: "Alt+3: Go to selection actions",
        ctrl_shift_s: "Ctrl+Shift+S: Activate multi-selection",
        ctrl_shift_v: "Ctrl+Shift+V: Toggle view",
        c_categorize: "C: Categorize (in expense list)",
        s_status: "S: Change status (in expense list)",
        d_duplicate: "D: Duplicate (in expense list)",
        del_delete: "Del: Delete (in expense list)",
        press_enter_edit: "Press Enter to edit this expense",
        press_enter_delete: "Press Enter to delete this expense. You can restore it from history.",
        press_enter_duplicate: "Press Enter to create a copy of this expense",
        press_enter_status: "Press Enter to change expense status",
        press_enter_category: "Press Enter to change expense category",
        press_enter_execute: "Press Enter to execute this action"
      }
    },
    bulk_operations: {
      operations: {
        categorize: "Categorize Expenses",
        status: "Update Status",
        delete: "Delete Expenses",
        execute: "Execute"
      },
      notifications: {
        completed: "Operation completed successfully"
      },
      errors: {
        connection: "Connection error. Please try again.",
        no_operation_selected: "Please select an operation type",
        no_category_selected: "Please select a category",
        no_status_selected: "Please select a status",
        confirm_deletion: "Please confirm deletion",
        invalid_operation: "Invalid operation",
        processing_error: "An error occurred while processing the operation"
      },
      progress: {
        processing: "Processing %{count} expenses..."
      },
      partial_errors: {
        items_failed: "%{count} expenses could not be processed",
        expense_item: "Expense #%{id}: %{error}",
        more_items: "... and %{count} more"
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
