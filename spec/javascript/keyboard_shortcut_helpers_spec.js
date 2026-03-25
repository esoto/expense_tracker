import {
  shouldSuppressShortcut,
  isTypingInFormField
} from "../../app/javascript/utilities/keyboard_shortcut_helpers"

/**
 * Helpers to create minimal keyboard events with a specific target element.
 *
 * KeyboardEvent does not accept a `target` via its constructor; we proxy the
 * property so tests can pass a real or synthetic Element as the target without
 * having to dispatch the event through the DOM.
 */
function makeEvent(key, targetElement) {
  const event = new KeyboardEvent("keydown", { key, bubbles: true })
  Object.defineProperty(event, "target", { value: targetElement, writable: false })
  return event
}

function makeElementEvent(key, tagName, attributes = {}) {
  const el = document.createElement(tagName)
  Object.entries(attributes).forEach(([attr, value]) => el.setAttribute(attr, value))
  const event = makeEvent(key, el)
  return event
}

// ---------------------------------------------------------------------------
// isTypingInFormField
// ---------------------------------------------------------------------------

describe("isTypingInFormField", () => {
  describe("returns true for text-entry form elements", () => {
    it("returns true when target is a text input", () => {
      const event = makeElementEvent("a", "input", { type: "text" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is an email input", () => {
      const event = makeElementEvent("a", "input", { type: "email" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is a password input", () => {
      const event = makeElementEvent("a", "input", { type: "password" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is a number input", () => {
      const event = makeElementEvent("a", "input", { type: "number" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is a search input", () => {
      const event = makeElementEvent("a", "input", { type: "search" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is a textarea", () => {
      const event = makeElementEvent("a", "textarea")
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target is a select", () => {
      const event = makeElementEvent("a", "select")
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target has contenteditable (true value)", () => {
      const event = makeElementEvent("a", "div", { contenteditable: "true" })
      expect(isTypingInFormField(event)).toBe(true)
    })

    it("returns true when target has contenteditable with empty string (browser default)", () => {
      const event = makeElementEvent("a", "div", { contenteditable: "" })
      expect(isTypingInFormField(event)).toBe(true)
    })
  })

  describe("returns false for non-text-entry form controls", () => {
    it("returns false when target is a checkbox input", () => {
      const event = makeElementEvent("a", "input", { type: "checkbox" })
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is a radio input", () => {
      const event = makeElementEvent("a", "input", { type: "radio" })
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is a button input", () => {
      const event = makeElementEvent("a", "input", { type: "button" })
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is a submit input", () => {
      const event = makeElementEvent("a", "input", { type: "submit" })
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is a reset input", () => {
      const event = makeElementEvent("a", "input", { type: "reset" })
      expect(isTypingInFormField(event)).toBe(false)
    })
  })

  describe("returns false for non-form elements", () => {
    it("returns false when target is a div", () => {
      const event = makeElementEvent("a", "div")
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is a button element", () => {
      const event = makeElementEvent("a", "button")
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target is an anchor", () => {
      const event = makeElementEvent("a", "a")
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when target has contenteditable='false'", () => {
      const event = makeElementEvent("a", "div", { contenteditable: "false" })
      expect(isTypingInFormField(event)).toBe(false)
    })
  })

  describe("instanceof Element guard", () => {
    it("returns false when event target is not an Element (e.g., document)", () => {
      const event = makeEvent("a", document)
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when event target is window", () => {
      const event = makeEvent("a", window)
      expect(isTypingInFormField(event)).toBe(false)
    })

    it("returns false when event target is null", () => {
      const event = makeEvent("a", null)
      expect(isTypingInFormField(event)).toBe(false)
    })
  })
})

// ---------------------------------------------------------------------------
// shouldSuppressShortcut
// ---------------------------------------------------------------------------

describe("shouldSuppressShortcut", () => {
  describe("Escape key is never suppressed", () => {
    it("returns false for Escape when target is an input (always allowed)", () => {
      const event = makeElementEvent("Escape", "input", { type: "text" })
      expect(shouldSuppressShortcut(event)).toBe(false)
    })

    it("returns false for Escape when target is a textarea", () => {
      const event = makeElementEvent("Escape", "textarea")
      expect(shouldSuppressShortcut(event)).toBe(false)
    })

    it("returns false for Escape when target is a select", () => {
      const event = makeElementEvent("Escape", "select")
      expect(shouldSuppressShortcut(event)).toBe(false)
    })

    it("returns false for Escape when target is a plain div", () => {
      const event = makeElementEvent("Escape", "div")
      expect(shouldSuppressShortcut(event)).toBe(false)
    })
  })

  describe("suppresses shortcuts when typing in form fields", () => {
    it("returns true when target is an input element", () => {
      const event = makeElementEvent("k", "input", { type: "text" })
      expect(shouldSuppressShortcut(event)).toBe(true)
    })

    it("returns true when target is a textarea", () => {
      const event = makeElementEvent("n", "textarea")
      expect(shouldSuppressShortcut(event)).toBe(true)
    })

    it("returns true when target is a select", () => {
      const event = makeElementEvent("s", "select")
      expect(shouldSuppressShortcut(event)).toBe(true)
    })

    it("returns true when target has contenteditable attribute", () => {
      const event = makeElementEvent("e", "div", { contenteditable: "true" })
      expect(shouldSuppressShortcut(event)).toBe(true)
    })
  })

  describe("allows shortcuts when not in form fields", () => {
    it("returns false when target is a regular div", () => {
      const event = makeElementEvent("k", "div")
      expect(shouldSuppressShortcut(event)).toBe(false)
    })

    it("returns false when target is a button element", () => {
      const event = makeElementEvent("k", "button")
      expect(shouldSuppressShortcut(event)).toBe(false)
    })

    it("returns false when target is the document (non-Element)", () => {
      const event = makeEvent("k", document)
      expect(shouldSuppressShortcut(event)).toBe(false)
    })
  })

  describe("allowInFormFields option", () => {
    it("returns false even inside an input when allowInFormFields is true", () => {
      const event = makeElementEvent("k", "input", { type: "text" })
      expect(shouldSuppressShortcut(event, { allowInFormFields: true })).toBe(false)
    })

    it("returns false even inside a textarea when allowInFormFields is true", () => {
      const event = makeElementEvent("k", "textarea")
      expect(shouldSuppressShortcut(event, { allowInFormFields: true })).toBe(false)
    })

    it("defaults allowInFormFields to false when no options are passed", () => {
      const event = makeElementEvent("k", "input", { type: "text" })
      // Should suppress because typing in an input — same as calling with default options
      expect(shouldSuppressShortcut(event)).toBe(true)
    })

    it("defaults allowInFormFields to false when an empty options object is passed", () => {
      const event = makeElementEvent("k", "input", { type: "text" })
      expect(shouldSuppressShortcut(event, {})).toBe(true)
    })
  })
})
