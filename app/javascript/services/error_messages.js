// Error message mapping service for user-friendly error handling.
// Translations are loaded lazily from the DOM via the data-sync-widget-messages-value
// attribute placed on the sync widget root element by sync_widget_messages (Rails helper).
export class ErrorMessages {
  constructor() {
    this._messages = null
  }

  // ---------------------------------------------------------------------------
  // Lazy DOM loader
  // ---------------------------------------------------------------------------

  get messages() {
    if (this._messages !== null) return this._messages

    try {
      const el = document.querySelector('[data-sync-widget-messages-value]')
      if (!el) return {}
      const raw = el.getAttribute('data-sync-widget-messages-value')
      if (!raw) return {}
      this._messages = JSON.parse(raw)
      return this._messages
    } catch (_) {
      // Parse failed — do not cache so we retry on next lookup (widget may
      // not yet be in the DOM on first call).
      return {}
    }
  }

  // ---------------------------------------------------------------------------
  // Public API (signatures unchanged)
  // ---------------------------------------------------------------------------

  // Get message by error code, optionally scoped to a category.
  // Falls back to generic heuristics, then the raw errorCode key.
  getMessage(errorCode, category = null) {
    const msgs = this.messages

    // 1. Category-scoped lookup
    if (category && msgs[category] && msgs[category][errorCode]) {
      return msgs[category][errorCode]
    }

    // 2. Search all categories
    for (const cat in msgs) {
      if (msgs[cat] && typeof msgs[cat] === 'object' && msgs[cat][errorCode]) {
        return msgs[cat][errorCode]
      }
    }

    // 3. Generic heuristics
    const generic = msgs.generic || {}
    if (errorCode && typeof errorCode === 'string') {
      if (errorCode.includes('network') || errorCode.includes('connection')) {
        return generic.network || errorCode
      }
      if (errorCode.includes('server') || errorCode.includes('500')) {
        return generic.server || errorCode
      }
      if (errorCode.includes('client') || errorCode.includes('400')) {
        return generic.client || errorCode
      }
    }

    // 4. Final fallback — return the key itself (matches services/i18n.js convention)
    return generic.unknown || errorCode
  }

  // Get action label text
  getAction(action) {
    const actions = this.messages.actions || {}
    return actions[action] || action
  }

  // Get status label text
  getStatus(status) {
    const statusMap = this.messages.status || {}
    return statusMap[status] || status
  }

  // Get suggestion text for an error type
  getSuggestion(errorType) {
    const suggestions = this.messages.suggestions || {}
    return suggestions[errorType] || ""
  }

  // Format message with %{var} interpolation
  format(message, params = {}) {
    let formatted = message

    for (const key in params) {
      const placeholder = `%{${key}}`
      formatted = formatted.replace(placeholder, params[key])
    }

    return formatted
  }
}

// Export singleton instance
export default new ErrorMessages()
