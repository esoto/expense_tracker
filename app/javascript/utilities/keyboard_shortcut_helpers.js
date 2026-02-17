/**
 * Keyboard Shortcut Helpers
 *
 * Shared utility functions for standardizing keyboard shortcut behavior
 * across all Stimulus controllers in the application.
 *
 * Task 3.10: Standardize Keyboard Shortcuts
 *
 * Rules:
 * 1. Shortcuts MUST NOT fire when the user is typing in form fields
 * 2. Single-letter shortcuts MUST be scoped to their relevant UI context
 * 3. Global shortcuts (Ctrl/Cmd combos) should still check for form fields
 * 4. Escape is always allowed (universally expected to close/cancel)
 */

/**
 * Checks whether the currently focused element is a form field where
 * the user is likely typing text. Keyboard shortcuts should generally
 * be suppressed in this situation.
 *
 * @param {Event} event - The keyboard event
 * @returns {boolean} true if the event target is a text-entry form field
 */
export function isTypingInFormField(event) {
  const target = event.target
  if (!target) return false

  return target.matches(
    'input:not([type="checkbox"]):not([type="radio"]):not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="range"]), ' +
    'textarea, ' +
    'select, ' +
    '[contenteditable="true"], ' +
    '[contenteditable=""]'
  )
}

/**
 * Determines whether a keyboard shortcut should be suppressed.
 * Escape is always allowed. Modifier-based shortcuts (Ctrl/Cmd) are allowed
 * in form fields (browsers rely on them for copy/paste/undo, etc.).
 * Single-key shortcuts are suppressed in form fields.
 *
 * @param {KeyboardEvent} event - The keyboard event
 * @param {Object} options
 * @param {boolean} [options.allowInFormFields=false] - Force-allow even in form fields
 * @returns {boolean} true if the shortcut should be suppressed (do not handle)
 */
export function shouldSuppressShortcut(event, { allowInFormFields = false } = {}) {
  // Escape is always allowed everywhere
  if (event.key === 'Escape') return false

  // If explicitly allowed, never suppress
  if (allowInFormFields) return false

  return isTypingInFormField(event)
}
