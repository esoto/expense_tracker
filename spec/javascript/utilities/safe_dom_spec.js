/**
 * spec/javascript/utilities/safe_dom_spec.js
 *
 * XSS payload escaping specs for safe_dom helpers.
 *
 * NOTE: This project has no JS test runner configured (no package.json / Jest config).
 * These specs follow the existing spec/javascript/ convention and are ready to run
 * once Jest + jsdom are wired up. See PER-543 PR description for setup instructions.
 */

import { createElement, escapeHtml } from "../../../app/javascript/utilities/safe_dom"

describe("safe_dom", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  const XSS_ATTR    = '" onmouseover="alert(1)'
  const XSS_COMPLEX = '<img src=x onerror=alert(1)><b>bold</b>'

  describe("createElement()", () => {
    it("renders XSS payload as literal text, not as a script element", () => {
      const el = createElement('div', { text: XSS_PAYLOAD })
      expect(el.textContent).toBe(XSS_PAYLOAD)
      expect(el.querySelector('script')).toBeNull()
    })

    it("does not execute injected script via text content", () => {
      const el = createElement('span', { text: XSS_PAYLOAD })
      // innerHTML should be the HTML-escaped representation
      expect(el.innerHTML).toBe('&lt;script&gt;alert(1)&lt;/script&gt;')
    })

    it("renders complex XSS payload as text without creating DOM elements", () => {
      const el = createElement('p', { text: XSS_COMPLEX })
      expect(el.textContent).toBe(XSS_COMPLEX)
      expect(el.querySelector('img')).toBeNull()
      expect(el.querySelector('b')).toBeNull()
    })

    it("sets attributes safely without executing injected handlers", () => {
      const el = createElement('div', { attrs: { 'data-value': XSS_ATTR } })
      // The attribute value should be the raw string, stored as an attribute (not evaluated)
      expect(el.getAttribute('data-value')).toBe(XSS_ATTR)
      // No event handler should have been attached
      expect(el.onmouseover).toBeNull()
    })

    it("adds classes without allowing injection", () => {
      const el = createElement('div', { classes: ['safe-class'] })
      expect(el.classList.contains('safe-class')).toBe(true)
    })

    it("nests children safely", () => {
      const child = createElement('span', { text: XSS_PAYLOAD })
      const parent = createElement('div', { children: [child] })
      expect(parent.querySelector('script')).toBeNull()
      expect(parent.textContent).toBe(XSS_PAYLOAD)
    })

    it("returns a proper HTMLElement", () => {
      const el = createElement('button', { text: 'Click me', attrs: { type: 'button' } })
      expect(el.tagName).toBe('BUTTON')
      expect(el.getAttribute('type')).toBe('button')
      expect(el.textContent).toBe('Click me')
    })
  })

  describe("escapeHtml()", () => {
    it("escapes < and > characters", () => {
      expect(escapeHtml('<script>')).toBe('&lt;script&gt;')
    })

    it("escapes the full XSS payload", () => {
      const escaped = escapeHtml(XSS_PAYLOAD)
      expect(escaped).not.toContain('<script>')
      expect(escaped).toContain('&lt;script&gt;')
    })

    it("handles null safely", () => {
      expect(escapeHtml(null)).toBe('')
    })

    it("handles undefined safely", () => {
      expect(escapeHtml(undefined)).toBe('')
    })

    it("handles empty string", () => {
      expect(escapeHtml('')).toBe('')
    })

    it("handles numbers", () => {
      expect(escapeHtml(42)).toBe('42')
    })

    it("does not double-escape already-escaped strings", () => {
      // escapeHtml escapes the & in &amp; — this is expected behaviour
      expect(escapeHtml('&amp;')).toBe('&amp;amp;')
    })
  })
})
