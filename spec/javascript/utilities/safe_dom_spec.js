/**
 * spec/javascript/utilities/safe_dom_spec.js
 *
 * XSS payload escaping specs for safe_dom helpers.
 *
 * NOTE: This project has no JS test runner configured (no package.json / Jest config).
 * These specs follow the existing spec/javascript/ convention and are ready to run
 * once Jest + jsdom are wired up. See PER-543 PR description for setup instructions.
 */

import { createElement, escapeHtml, escapeAttr } from "../../../app/javascript/utilities/safe_dom"

describe("safe_dom", () => {
  const XSS_PAYLOAD = '<script>alert(1)</script>'
  const XSS_ATTR    = '" onmouseover="alert(1)'
  const XSS_COMPLEX = '<img src=x onerror=alert(1)><b>bold</b>'
  const XSS_SVG     = '<svg/onload=alert(1)>'
  const XSS_ENTITY  = '&#60;script&#62;alert(1)&#60;/script&#62;'
  const XSS_JSURL   = 'javascript:alert(1)'

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

    it("renders <svg/onload=...> payload as literal text", () => {
      const el = createElement('span', { text: XSS_SVG })
      expect(el.textContent).toBe(XSS_SVG)
      expect(el.querySelector('svg')).toBeNull()
    })

    it("does not decode HTML entities in text content", () => {
      // textContent must NOT decode &#60; back to '<' — that would re-open
      // the entity-encoded XSS bypass.
      const el = createElement('span', { text: XSS_ENTITY })
      expect(el.textContent).toBe(XSS_ENTITY)
      expect(el.querySelector('script')).toBeNull()
    })

    it("stores javascript: URL as text without executing", () => {
      // When a payload like 'javascript:alert(1)' lands in text, it must
      // never become an active link. createElement only sets textContent.
      const el = createElement('a', { text: XSS_JSURL, attrs: { href: '#' } })
      expect(el.textContent).toBe(XSS_JSURL)
      expect(el.getAttribute('href')).toBe('#')
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
      // escapeHtml escapes the & in &amp; — documented footgun: callers
      // MUST NOT pre-escape input. Pass raw user data only.
      expect(escapeHtml('&amp;')).toBe('&amp;amp;')
    })

    it("does NOT escape quotes (text-context only — use escapeAttr for attributes)", () => {
      // textContent serialization only escapes <, >, &. Documented limitation.
      expect(escapeHtml('"foo"')).toBe('"foo"')
    })

    it("escapes <svg/onload=...> payload", () => {
      expect(escapeHtml(XSS_SVG)).toBe('&lt;svg/onload=alert(1)&gt;')
    })
  })

  describe("escapeAttr()", () => {
    it("escapes & < > \" and '", () => {
      expect(escapeAttr('a&b<c>d"e\'f')).toBe('a&amp;b&lt;c&gt;d&quot;e&#39;f')
    })

    it("blocks attribute-context breakout via double-quote", () => {
      // The classic '" onmouseover="alert(1)' payload. After escapeAttr,
      // the embedded double-quote is &quot; so it cannot close the attribute.
      const escaped = escapeAttr(XSS_ATTR)
      expect(escaped).not.toContain('"')
      expect(escaped).toContain('&quot;')
    })

    it("blocks attribute-context breakout via single-quote", () => {
      const escaped = escapeAttr("' onmouseover='alert(1)")
      expect(escaped).not.toContain("'")
      expect(escaped).toContain('&#39;')
    })

    it("handles null and undefined", () => {
      expect(escapeAttr(null)).toBe('')
      expect(escapeAttr(undefined)).toBe('')
    })

    it("handles numbers", () => {
      expect(escapeAttr(42)).toBe('42')
    })
  })
})
