/**
 * safe_dom.js — XSS-safe DOM construction helpers
 *
 * Preferred: use createElement() to build elements with textContent for text nodes.
 * Fallback: escapeHtml() for cases where a surrounding template is unavoidable.
 *
 * These utilities replace innerHTML assignments that interpolate user/admin data,
 * eliminating the XSS vector from template literals with dynamic content.
 *
 * See: PER-543 (harden 5 high-risk innerHTML sites)
 *      PER-539 (broader innerHTML sweep)
 */

/**
 * Create a DOM element safely.
 *
 * @param {string} tag - HTML tag name (e.g. 'div', 'span', 'button')
 * @param {Object} options
 * @param {string|null}   options.text     - Text content (uses textContent — never HTML)
 * @param {Object}        options.attrs    - Attribute key/value pairs (set via setAttribute)
 * @param {string[]}      options.classes  - CSS class names to add
 * @param {Element[]}     options.children - Child elements to append
 * @returns {HTMLElement}
 */
export function createElement(tag, { text = null, attrs = {}, classes = [], children = [] } = {}) {
  const el = document.createElement(tag)
  if (text !== null) el.textContent = text
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
  if (classes.length) el.classList.add(...classes)
  for (const child of children) el.appendChild(child)
  return el
}

/**
 * Escape a string for safe insertion as HTML text content.
 * Prefer createElement() with text: instead — this is only for cases where
 * the surrounding structural HTML is unavoidable (e.g. SVG paths).
 *
 * IMPORTANT: this is for TEXT context only. The textContent→innerHTML
 * round-trip does NOT escape quotes, so embedding the result inside an
 * attribute value (e.g. `<div title="${escapeHtml(x)}">`) is unsafe.
 * Use escapeAttr() for attribute context.
 *
 * @param {string|null|undefined} str
 * @returns {string} HTML-escaped string (text context)
 */
export function escapeHtml(str) {
  const div = document.createElement('div')
  div.textContent = String(str ?? '')
  return div.innerHTML
}

/**
 * Escape a string for safe insertion inside an HTML attribute value.
 * Use this when interpolating user data into a template literal that
 * will be assigned to innerHTML inside an attribute context — e.g.
 * `<option value="${escapeAttr(id)}">` or `<div data-x="${escapeAttr(s)}">`.
 *
 * Escapes &, <, >, ", and ' so the attribute can use either single or
 * double-quote delimiters safely.
 *
 * @param {string|null|undefined} str
 * @returns {string} attribute-safe escaped string
 */
export function escapeAttr(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}
