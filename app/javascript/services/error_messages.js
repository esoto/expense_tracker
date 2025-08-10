// Error message mapping service for user-friendly error handling
export class ErrorMessages {
  constructor(locale = 'es') {
    this.locale = locale
    this.messages = this.loadMessages()
  }

  loadMessages() {
    const messages = {
      es: {
        // Connection errors
        connection: {
          failed: "No se pudo conectar al servidor. Verificando conexión...",
          lost: "Se perdió la conexión con el servidor",
          timeout: "La conexión tardó demasiado tiempo. Reintentando...",
          refused: "El servidor rechazó la conexión",
          network: "Error de red. Verifica tu conexión a internet",
          offline: "Sin conexión a internet",
          online: "Conexión restaurada",
          websocket_unsupported: "Tu navegador no soporta conexiones en tiempo real. Usando modo de actualización periódica.",
          firewall: "La conexión podría estar bloqueada por un firewall. Usando modo alternativo.",
          ssl: "Error de certificado SSL. Contacta al administrador."
        },

        // Authentication errors
        auth: {
          expired: "Tu sesión ha expirado. Por favor, recarga la página",
          invalid: "Credenciales inválidas. Por favor, inicia sesión nuevamente",
          unauthorized: "No tienes permisos para acceder a este recurso",
          token_invalid: "Token de seguridad inválido",
          token_expired: "Token de seguridad expirado"
        },

        // Sync-specific errors
        sync: {
          email_connection: "No se pudo conectar con el servidor de correo",
          email_auth: "Error de autenticación con el correo. Verifica tus credenciales",
          rate_limit: "Demasiadas solicitudes. Esperando antes de continuar...",
          parsing_error: "Error al procesar los correos electrónicos",
          duplicate_detected: "Se detectaron transacciones duplicadas",
          no_emails: "No se encontraron correos nuevos para sincronizar",
          account_locked: "La cuenta de correo está bloqueada temporalmente",
          quota_exceeded: "Se excedió el límite de sincronización diario",
          processing_error: "Error al procesar las transacciones",
          invalid_format: "Formato de correo no reconocido"
        },

        // Server errors
        server: {
          internal: "Error interno del servidor. El equipo ha sido notificado",
          maintenance: "El servicio está en mantenimiento. Intenta más tarde",
          overloaded: "El servidor está sobrecargado. Reintentando...",
          unavailable: "Servicio temporalmente no disponible",
          timeout: "El servidor no respondió a tiempo"
        },

        // Recovery messages
        recovery: {
          retrying: "Reintentando conexión...",
          retry_in: "Reintentando en %{seconds} segundos",
          max_retries: "Se alcanzó el máximo de intentos",
          manual_retry: "Haz clic para reintentar",
          recovered: "Conexión recuperada exitosamente",
          switching_mode: "Cambiando a modo de actualización periódica",
          degraded_mode: "Funcionando en modo limitado"
        },

        // Action messages
        actions: {
          retry: "Reintentar",
          dismiss: "Cerrar",
          reload: "Recargar página",
          check_connection: "Verificar conexión",
          contact_support: "Contactar soporte",
          view_details: "Ver detalles",
          report_issue: "Reportar problema"
        },

        // Status messages
        status: {
          connecting: "Conectando...",
          connected: "Conectado",
          disconnected: "Desconectado",
          reconnecting: "Reconectando...",
          syncing: "Sincronizando...",
          paused: "Pausado",
          completed: "Completado",
          failed: "Error"
        }
      },

      en: {
        // Connection errors
        connection: {
          failed: "Could not connect to server. Checking connection...",
          lost: "Lost connection to server",
          timeout: "Connection timed out. Retrying...",
          refused: "Server refused connection",
          network: "Network error. Check your internet connection",
          offline: "No internet connection",
          online: "Connection restored",
          websocket_unsupported: "Your browser doesn't support real-time connections. Using periodic update mode.",
          firewall: "Connection might be blocked by a firewall. Using alternative mode.",
          ssl: "SSL certificate error. Contact administrator."
        },

        // Authentication errors
        auth: {
          expired: "Your session has expired. Please reload the page",
          invalid: "Invalid credentials. Please login again",
          unauthorized: "You don't have permission to access this resource",
          token_invalid: "Invalid security token",
          token_expired: "Security token expired"
        },

        // Sync-specific errors
        sync: {
          email_connection: "Could not connect to email server",
          email_auth: "Email authentication error. Check your credentials",
          rate_limit: "Too many requests. Waiting before continuing...",
          parsing_error: "Error processing emails",
          duplicate_detected: "Duplicate transactions detected",
          no_emails: "No new emails found to sync",
          account_locked: "Email account is temporarily locked",
          quota_exceeded: "Daily sync limit exceeded",
          processing_error: "Error processing transactions",
          invalid_format: "Unrecognized email format"
        },

        // Server errors
        server: {
          internal: "Internal server error. Team has been notified",
          maintenance: "Service is under maintenance. Try again later",
          overloaded: "Server is overloaded. Retrying...",
          unavailable: "Service temporarily unavailable",
          timeout: "Server did not respond in time"
        },

        // Recovery messages
        recovery: {
          retrying: "Retrying connection...",
          retry_in: "Retrying in %{seconds} seconds",
          max_retries: "Maximum retries reached",
          manual_retry: "Click to retry",
          recovered: "Connection recovered successfully",
          switching_mode: "Switching to periodic update mode",
          degraded_mode: "Running in limited mode"
        },

        // Action messages
        actions: {
          retry: "Retry",
          dismiss: "Dismiss",
          reload: "Reload page",
          check_connection: "Check connection",
          contact_support: "Contact support",
          view_details: "View details",
          report_issue: "Report issue"
        },

        // Status messages
        status: {
          connecting: "Connecting...",
          connected: "Connected",
          disconnected: "Disconnected",
          reconnecting: "Reconnecting...",
          syncing: "Syncing...",
          paused: "Paused",
          completed: "Completed",
          failed: "Failed"
        }
      }
    }

    return messages[this.locale] || messages.es
  }

  // Get message by error code or type
  getMessage(errorCode, category = null) {
    // Try to find specific error message
    if (category && this.messages[category] && this.messages[category][errorCode]) {
      return this.messages[category][errorCode]
    }

    // Search all categories for the error code
    for (const cat in this.messages) {
      if (this.messages[cat][errorCode]) {
        return this.messages[cat][errorCode]
      }
    }

    // Return generic error message
    return this.getGenericMessage(errorCode)
  }

  // Get generic error message based on error type
  getGenericMessage(errorCode) {
    const genericMessages = {
      es: {
        network: "Error de conexión. Por favor, intenta de nuevo.",
        server: "Error del servidor. Por favor, intenta más tarde.",
        client: "Error en la aplicación. Por favor, recarga la página.",
        unknown: "Ocurrió un error inesperado."
      },
      en: {
        network: "Connection error. Please try again.",
        server: "Server error. Please try again later.",
        client: "Application error. Please reload the page.",
        unknown: "An unexpected error occurred."
      }
    }

    const messages = genericMessages[this.locale] || genericMessages.es
    
    // Try to determine error type from code
    if (errorCode && typeof errorCode === 'string') {
      if (errorCode.includes('network') || errorCode.includes('connection')) {
        return messages.network
      }
      if (errorCode.includes('server') || errorCode.includes('500')) {
        return messages.server
      }
      if (errorCode.includes('client') || errorCode.includes('400')) {
        return messages.client
      }
    }

    return messages.unknown
  }

  // Get action text
  getAction(action) {
    return this.messages.actions[action] || action
  }

  // Get status text
  getStatus(status) {
    return this.messages.status[status] || status
  }

  // Format message with parameters
  format(message, params = {}) {
    let formatted = message
    
    for (const key in params) {
      const placeholder = `%{${key}}`
      formatted = formatted.replace(placeholder, params[key])
    }
    
    return formatted
  }

  // Map HTTP status codes to user-friendly messages
  getHttpErrorMessage(statusCode) {
    const httpMessages = {
      es: {
        400: "Solicitud incorrecta. Verifica los datos enviados.",
        401: "No autorizado. Por favor, inicia sesión.",
        403: "Acceso prohibido. No tienes permisos para esta acción.",
        404: "Recurso no encontrado.",
        408: "La solicitud tardó demasiado tiempo.",
        429: "Demasiadas solicitudes. Por favor, espera un momento.",
        500: "Error interno del servidor.",
        502: "Error de conexión con el servidor.",
        503: "Servicio no disponible temporalmente.",
        504: "El servidor no respondió a tiempo."
      },
      en: {
        400: "Bad request. Check the submitted data.",
        401: "Unauthorized. Please log in.",
        403: "Access forbidden. You don't have permission for this action.",
        404: "Resource not found.",
        408: "Request timed out.",
        429: "Too many requests. Please wait a moment.",
        500: "Internal server error.",
        502: "Server connection error.",
        503: "Service temporarily unavailable.",
        504: "Server did not respond in time."
      }
    }

    const messages = httpMessages[this.locale] || httpMessages.es
    return messages[statusCode] || this.getGenericMessage('server')
  }

  // Get suggestion for error recovery
  getSuggestion(errorType) {
    const suggestions = {
      es: {
        network: "Verifica tu conexión a internet e intenta de nuevo.",
        auth: "Por favor, recarga la página e inicia sesión nuevamente.",
        rate_limit: "Espera unos minutos antes de intentar de nuevo.",
        server: "El problema es temporal. Intenta de nuevo en unos minutos.",
        email: "Verifica que las credenciales del correo sean correctas.",
        parsing: "Algunos correos no pudieron ser procesados. Contacta soporte si persiste."
      },
      en: {
        network: "Check your internet connection and try again.",
        auth: "Please reload the page and log in again.",
        rate_limit: "Wait a few minutes before trying again.",
        server: "This is a temporary issue. Try again in a few minutes.",
        email: "Verify that your email credentials are correct.",
        parsing: "Some emails could not be processed. Contact support if this persists."
      }
    }

    const userSuggestions = suggestions[this.locale] || suggestions.es
    return userSuggestions[errorType] || ""
  }
}

// Export singleton instance
export default new ErrorMessages(document.documentElement.lang || 'es')