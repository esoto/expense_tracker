import { Controller } from "@hotwired/stimulus"

// Keeps a native <input type="color"> and a sibling hex text field in
// sync so the category form supports either direct typing (#0f766e) or
// graphical selection. Preview swatch updates on every change.
//
// Targets:
//   - picker: the <input type="color"> element
//   - text:   the text field that actually submits the form value
//   - swatch: a visual preview block (optional)
//
// The text field is the source of truth (it is the form input). The
// picker mirrors it. Typing a valid hex updates the picker + swatch;
// picking a color via the OS dialog updates the text + swatch.
export default class extends Controller {
  static targets = ["picker", "text", "swatch"]

  connect() {
    this.syncFromText()
  }

  pickerChanged() {
    this.textTarget.value = this.pickerTarget.value
    this.updateSwatch(this.pickerTarget.value)
  }

  textChanged() {
    const value = this.textTarget.value.trim()
    if (this.isValidHex(value)) {
      this.pickerTarget.value = this.expandShortHex(value)
      this.updateSwatch(value)
    }
  }

  syncFromText() {
    const value = this.textTarget.value.trim()
    if (this.isValidHex(value)) {
      this.pickerTarget.value = this.expandShortHex(value)
      this.updateSwatch(value)
    } else {
      this.updateSwatch("#94a3b8") // slate-400 fallback
    }
  }

  updateSwatch(value) {
    if (this.hasSwatchTarget) {
      this.swatchTarget.style.backgroundColor = value
    }
  }

  isValidHex(value) {
    return /^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/.test(value)
  }

  // <input type="color"> requires a 6-char hex, so expand shorthand
  // like #f00 → #ff0000 before assigning.
  expandShortHex(value) {
    if (value.length === 4) {
      const [, r, g, b] = value
      return `#${r}${r}${g}${g}${b}${b}`
    }
    return value
  }
}
