import errorMessages from "services/error_messages"

/**
 * SyncErrorClassifier — standalone service for error analysis and classification.
 *
 * Extracts error-analysis logic from the widget controller so it can be tested
 * independently and reused by both the widget and the connection mixin.
 */
export class SyncErrorClassifier {
  /**
   * Analyze a raw error object and return a structured descriptor.
   *
   * @param {Error|object} error
   * @returns {{ type: string, message: string, status: string, recoverable: boolean }}
   */
  static analyzeError(error) {
    const errorString = error?.toString() || ''
    const errorMessage = error?.message || ''

    if (errorString.includes('NetworkError') || errorString.includes('ERR_NETWORK')) {
      return {
        type: 'network',
        message: errorMessages.getMessage('network', 'connection'),
        status: errorMessages.getMessage('offline', 'connection'),
        recoverable: true
      }
    }

    if (errorString.includes('SecurityError') || errorString.includes('ERR_CERT')) {
      return {
        type: 'ssl',
        message: errorMessages.getMessage('ssl', 'connection'),
        status: 'Error SSL',
        recoverable: false
      }
    }

    if (errorMessage.includes('401') || errorMessage.includes('Unauthorized')) {
      return {
        type: 'auth',
        message: errorMessages.getMessage('expired', 'auth'),
        status: errorMessages.getMessage('unauthorized', 'auth'),
        recoverable: false
      }
    }

    if (errorMessage.includes('500') || errorMessage.includes('Internal')) {
      return {
        type: 'server',
        message: errorMessages.getMessage('internal', 'server'),
        status: errorMessages.getMessage('unavailable', 'server'),
        recoverable: true
      }
    }

    // Default / unknown
    return {
      type: 'unknown',
      message: errorMessages.getMessage('failed', 'connection'),
      status: errorMessages.getStatus('failed'),
      recoverable: true
    }
  }

  /**
   * Determine why a channel subscription was rejected by inspecting the DOM.
   *
   * @param {Element} element  — the controller's root element
   * @returns {string}  error type key ('auth', etc.)
   */
  static determineRejectionReason(element) {
    const currentTime = Date.now()
    const sessionAge = currentTime - (element?.dataset?.sessionCreatedAt || currentTime)

    if (sessionAge > 86400000) {
      return 'auth'
    }

    if (!document.querySelector('[name="csrf-token"]')?.content) {
      return 'auth'
    }

    return 'auth'
  }

  /**
   * Return a user-facing error message for a given error type key.
   *
   * @param {string} errorType
   * @returns {string}
   */
  static getErrorMessage(errorType) {
    return errorMessages.getMessage(
      errorType === 'auth' ? 'expired' : 'refused',
      errorType
    )
  }

  /**
   * Handle a sync-specific error: show a toast, log it, and optionally report it.
   *
   * @param {object} error  — { code, type, message, details }
   * @param {{ showToast: Function, log: Function, sendErrorToServer: Function }} callbacks
   */
  static handleSyncError(error, callbacks) {
    const { showToast, log, sendErrorToServer } = callbacks
    const errorCode = error.code || error.type || 'unknown'

    const syncErrorMap = {
      email_connection: errorMessages.getMessage('email_connection', 'sync'),
      email_auth: errorMessages.getMessage('email_auth', 'sync'),
      rate_limit: errorMessages.getMessage('rate_limit', 'sync'),
      parsing_error: errorMessages.getMessage('parsing_error', 'sync'),
      duplicate: errorMessages.getMessage('duplicate_detected', 'sync'),
      no_emails: errorMessages.getMessage('no_emails', 'sync'),
      quota_exceeded: errorMessages.getMessage('quota_exceeded', 'sync')
    }

    const message = syncErrorMap[errorCode] || errorMessages.getMessage('processing_error', 'sync')
    const suggestion = errorMessages.getSuggestion(
      errorCode.includes('email') ? 'email' : 'server'
    )

    const severity = (errorCode === 'rate_limit' || errorCode === 'quota_exceeded')
      ? 'warning'
      : 'error'

    if (showToast) showToast(`${message}. ${suggestion}`, severity, 8000)
    if (log) log('error', `Sync error: ${errorCode}`, error)
    if (sendErrorToServer) sendErrorToServer(`Sync error: ${errorCode}`, error)
  }
}
