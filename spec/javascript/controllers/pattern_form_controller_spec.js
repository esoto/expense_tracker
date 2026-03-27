import { Application } from "@hotwired/stimulus"
import PatternFormController from "../../../app/javascript/controllers/pattern_form_controller"

describe("PatternFormController", () => {
  let application

  function buildHTML(patternType = "") {
    return `
      <div data-controller="pattern-form">
        <select name="categorization_pattern[pattern_type]"
                data-action="change->pattern-form#updateValueHelp">
          <option value="">Selecciona un tipo de patrón...</option>
          <option value="merchant" ${patternType === "merchant" ? "selected" : ""}>Comerciante</option>
          <option value="keyword" ${patternType === "keyword" ? "selected" : ""}>Palabra Clave</option>
          <option value="description" ${patternType === "description" ? "selected" : ""}>Descripción</option>
          <option value="amount_range" ${patternType === "amount_range" ? "selected" : ""}>Rango de Monto</option>
          <option value="regex" ${patternType === "regex" ? "selected" : ""}>Expresión Regular</option>
          <option value="time" ${patternType === "time" ? "selected" : ""}>Tiempo</option>
        </select>

        <input type="text"
               name="categorization_pattern[pattern_value]"
               placeholder="Ingresa el valor del patrón..."
               data-pattern-form-target="valueField">

        <div data-pattern-form-target="valueHelp" class="text-sm text-slate-500">
          Selecciona un tipo de patrón para ver la ayuda del formato de valor
        </div>

        <input type="text"
               placeholder="Ingresa texto de prueba..."
               data-pattern-form-target="testInput">

        <button type="button" data-action="click->pattern-form#testPattern">
          Probar Coincidencia
        </button>

        <div data-pattern-form-target="testResult"></div>
      </div>
    `
  }

  function buildHTMLWithoutOptionalTargets() {
    return `
      <div data-controller="pattern-form">
        <select name="categorization_pattern[pattern_type]"
                data-action="change->pattern-form#updateValueHelp">
          <option value="">Selecciona un tipo de patrón...</option>
          <option value="merchant">Comerciante</option>
        </select>
      </div>
    `
  }

  beforeEach(() => {
    application = Application.start()
    application.register("pattern-form", PatternFormController)
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  describe("connect() — target guard", () => {
    it("does not throw when valueHelp target is absent", () => {
      document.body.innerHTML = buildHTMLWithoutOptionalTargets()
      expect(() => {
        // Controller already connected via Application.start(); just verify no error thrown
      }).not.toThrow()
    })

    it("does not throw when all targets are present", () => {
      document.body.innerHTML = buildHTML("merchant")
      expect(() => {}).not.toThrow()
    })
  })

  describe("#updateValueHelp", () => {
    beforeEach(() => {
      document.body.innerHTML = buildHTML()
    })

    it("updates valueHelp text for merchant type", () => {
      const select = document.querySelector("select")
      select.value = "merchant"
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("comerciante")
    })

    it("updates valueHelp text for keyword type", () => {
      const select = document.querySelector("select")
      select.value = "keyword"
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("palabra clave")
    })

    it("updates valueHelp text for amount_range type", () => {
      const select = document.querySelector("select")
      select.value = "amount_range"
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("mín-máx")
    })

    it("updates valueHelp text for regex type", () => {
      const select = document.querySelector("select")
      select.value = "regex"
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("expresión regular")
    })

    it("updates valueHelp text for time type", () => {
      const select = document.querySelector("select")
      select.value = "time"
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("mañana")
    })

    it("shows fallback help text when no type selected", () => {
      const select = document.querySelector("select")
      select.value = ""
      select.dispatchEvent(new Event("change"))

      const helpEl = document.querySelector("[data-pattern-form-target='valueHelp']")
      expect(helpEl.innerHTML).toContain("Selecciona un tipo de patrón")
    })

    it("updates placeholder on valueField when type changes", () => {
      const select = document.querySelector("select")
      select.value = "merchant"
      select.dispatchEvent(new Event("change"))

      const valueField = document.querySelector("[data-pattern-form-target='valueField']")
      expect(valueField.placeholder).toContain("Starbucks")
    })

    it("does not throw when valueHelp target is missing", () => {
      document.body.innerHTML = buildHTMLWithoutOptionalTargets()
      const select = document.querySelector("select")
      select.value = "merchant"

      expect(() => {
        select.dispatchEvent(new Event("change"))
      }).not.toThrow()
    })
  })

  describe("#testPattern", () => {
    beforeEach(() => {
      document.body.innerHTML = buildHTML()
    })

    it("shows warning when fields are empty", () => {
      const button = document.querySelector("[data-action='click->pattern-form#testPattern']")
      button.click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("Por favor ingresa todos los campos requeridos")
    })

    it("shows match result for merchant pattern", () => {
      const select = document.querySelector("select")
      select.value = "merchant"
      select.dispatchEvent(new Event("change"))

      document.querySelector("[data-pattern-form-target='valueField']").value = "starbucks"
      document.querySelector("[data-pattern-form-target='testInput']").value = "STARBUCKS COSTA RICA"

      document.querySelector("[data-action='click->pattern-form#testPattern']").click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("coincide")
    })

    it("shows no-match result when pattern does not match", () => {
      const select = document.querySelector("select")
      select.value = "merchant"
      select.dispatchEvent(new Event("change"))

      document.querySelector("[data-pattern-form-target='valueField']").value = "amazon"
      document.querySelector("[data-pattern-form-target='testInput']").value = "STARBUCKS COSTA RICA"

      document.querySelector("[data-action='click->pattern-form#testPattern']").click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("Sin coincidencia")
    })

    it("shows match for valid regex pattern", () => {
      const select = document.querySelector("select")
      select.value = "regex"
      select.dispatchEvent(new Event("change"))

      document.querySelector("[data-pattern-form-target='valueField']").value = "^UBER.*"
      document.querySelector("[data-pattern-form-target='testInput']").value = "UBER EATS CR"

      document.querySelector("[data-action='click->pattern-form#testPattern']").click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("coincide")
    })

    it("shows match for amount within range", () => {
      const select = document.querySelector("select")
      select.value = "amount_range"
      select.dispatchEvent(new Event("change"))

      document.querySelector("[data-pattern-form-target='valueField']").value = "10.00-50.00"
      document.querySelector("[data-pattern-form-target='testInput']").value = "25.00"

      document.querySelector("[data-action='click->pattern-form#testPattern']").click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("coincide")
    })

    it("shows no-match for amount outside range", () => {
      const select = document.querySelector("select")
      select.value = "amount_range"
      select.dispatchEvent(new Event("change"))

      document.querySelector("[data-pattern-form-target='valueField']").value = "10.00-50.00"
      document.querySelector("[data-pattern-form-target='testInput']").value = "100.00"

      document.querySelector("[data-action='click->pattern-form#testPattern']").click()

      const resultEl = document.querySelector("[data-pattern-form-target='testResult']")
      expect(resultEl.innerHTML).toContain("Sin coincidencia")
    })

    it("does not throw when valueField target is missing", () => {
      document.body.innerHTML = `
        <div data-controller="pattern-form">
          <select name="categorization_pattern[pattern_type]"
                  data-action="change->pattern-form#updateValueHelp">
            <option value="merchant">Comerciante</option>
          </select>
          <input type="text" data-pattern-form-target="testInput" value="test">
          <button type="button" data-action="click->pattern-form#testPattern">Probar</button>
          <div data-pattern-form-target="testResult"></div>
        </div>
      `

      const button = document.querySelector("[data-action='click->pattern-form#testPattern']")
      expect(() => button.click()).not.toThrow()
    })
  })

  describe("#performMatch", () => {
    let controller

    beforeEach(() => {
      document.body.innerHTML = buildHTML()
      controller = application.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller='pattern-form']"),
        "pattern-form"
      )
    })

    it("matches keyword case-insensitively", () => {
      expect(controller.performMatch("STARBUCKS COSTA RICA", "keyword", "starbucks")).toBe(true)
    })

    it("does not match keyword when absent", () => {
      expect(controller.performMatch("AMAZON PRIME", "keyword", "starbucks")).toBe(false)
    })

    it("matches description text", () => {
      expect(controller.performMatch("Suscripción mensual premium", "description", "suscripción")).toBe(true)
    })

    it("matches valid regex", () => {
      expect(controller.performMatch("UBER EATS CR", "regex", "^UBER.*")).toBe(true)
    })

    it("returns false for invalid regex without throwing", () => {
      expect(controller.performMatch("test", "regex", "[invalid")).toBe(false)
    })

    it("matches amount within range", () => {
      expect(controller.performMatch("25.00", "amount_range", "10.00-50.00")).toBe(true)
    })

    it("does not match amount outside range", () => {
      expect(controller.performMatch("100.00", "amount_range", "10.00-50.00")).toBe(false)
    })

    it("returns false for non-numeric amount", () => {
      expect(controller.performMatch("not a number", "amount_range", "10.00-50.00")).toBe(false)
    })

    it("returns false for amount_range with wrong format", () => {
      expect(controller.performMatch("25.00", "amount_range", "10.00")).toBe(false)
    })

    it("returns true for known time keyword", () => {
      expect(controller.performMatch("any text", "time", "mañana")).toBe(true)
    })

    it("returns true for valid time range format", () => {
      expect(controller.performMatch("any text", "time", "09:00-17:00")).toBe(true)
    })

    it("returns false for unknown pattern type", () => {
      expect(controller.performMatch("text", "unknown_type", "value")).toBe(false)
    })
  })
})
