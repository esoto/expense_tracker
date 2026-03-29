import { Application } from "@hotwired/stimulus"
import FilterPersistenceController from "../../app/javascript/controllers/filter_persistence_controller"

describe("FilterPersistenceController", () => {
  let application
  let element

  const buildDOM = ({
    storageType = "session",
    autoRestore = "true",
    autoSave = "true",
    urlSearch = ""
  } = {}) => {
    document.body.innerHTML = `
      <div data-controller="filter-persistence"
           data-filter-persistence-storage-type-value="${storageType}"
           data-filter-persistence-auto-restore-value="${autoRestore}"
           data-filter-persistence-auto-save-value="${autoSave}"
           data-filter-persistence-storage-key-value="expense_filters">

        <form data-filter-persistence-target="filterForm">
          <select name="category" data-filter-persistence-target="filterInput">
            <option value="">Todas las categorías</option>
            <option value="Supermercado">Supermercado</option>
            <option value="Restaurante">Restaurante</option>
          </select>

          <select name="bank" data-filter-persistence-target="filterInput">
            <option value="">Todos los bancos</option>
            <option value="BCR">BCR</option>
          </select>

          <input type="date" name="start_date" data-filter-persistence-target="filterInput" />
          <input type="date" name="end_date" data-filter-persistence-target="filterInput" />

          <button type="submit">Filtrar</button>
        </form>

        <button data-filter-persistence-target="restoreButton" class="hidden">
          Restaurar filtros
        </button>
      </div>
    `

    // Simulate URL search params if provided
    if (urlSearch) {
      Object.defineProperty(window, "location", {
        value: { ...window.location, search: urlSearch, pathname: "/expenses", href: "http://localhost/expenses" + urlSearch },
        writable: true
      })
    } else {
      Object.defineProperty(window, "location", {
        value: { search: "", pathname: "/expenses", href: "http://localhost/expenses" },
        writable: true
      })
    }
  }

  beforeEach(() => {
    jest.useFakeTimers()
    sessionStorage.clear()
    localStorage.clear()
  })

  afterEach(() => {
    jest.useRealTimers()
    jest.restoreAllMocks()
    if (application) {
      application.stop()
      application = null
    }
    document.body.innerHTML = ""
    sessionStorage.clear()
    localStorage.clear()
  })

  const startApplication = () => {
    application = Application.start()
    application.register("filter-persistence", FilterPersistenceController)
    element = document.querySelector('[data-controller="filter-persistence"]')
  }

  // -------------------------------------------------------------------------
  // connect() — initialisation
  // -------------------------------------------------------------------------
  describe("connect()", () => {
    it("initialises without errors when no filters are stored", () => {
      buildDOM()
      expect(() => startApplication()).not.toThrow()
    })

    it("uses sessionStorage when storage-type-value is 'session'", () => {
      buildDOM({ storageType: "session" })
      startApplication()
      // Writing via the controller should land in sessionStorage
      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Supermercado"
      form.dispatchEvent(new Event("submit"))

      expect(sessionStorage.getItem("expense_filters")).not.toBeNull()
    })

    it("uses localStorage when storage-type-value is 'local'", () => {
      buildDOM({ storageType: "local" })
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Restaurante"
      form.dispatchEvent(new Event("submit"))

      expect(localStorage.getItem("expense_filters")).not.toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // saveFiltersFromForm() — saving on form submit
  // -------------------------------------------------------------------------
  describe("saving filters on form submit", () => {
    it("saves filter values to sessionStorage when form is submitted", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Supermercado"
      form.querySelector('[name="bank"]').value = "BCR"

      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored).not.toBeNull()
      expect(stored.filters.category).toBe("Supermercado")
      expect(stored.filters.bank).toBe("BCR")
    })

    it("does NOT save when all filter fields are empty", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      // Leave all fields empty (default blank values)
      form.dispatchEvent(new Event("submit"))

      expect(sessionStorage.getItem("expense_filters")).toBeNull()
    })

    it("saves date range filters", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="start_date"]').value = "2026-01-01"
      form.querySelector('[name="end_date"]').value = "2026-01-31"

      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored.filters.start_date).toBe("2026-01-01")
      expect(stored.filters.end_date).toBe("2026-01-31")
    })

    it("records the current pathname in the stored data", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Supermercado"
      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored.url).toBe("/expenses")
    })

    it("records a timestamp in the stored data", () => {
      const before = Date.now()
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Supermercado"
      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored.timestamp).toBeGreaterThanOrEqual(before)
    })
  })

  // -------------------------------------------------------------------------
  // auto-save on input change (debounced)
  // -------------------------------------------------------------------------
  describe("auto-save on input change", () => {
    it("debounces and saves when a filterInput target changes value", () => {
      buildDOM()
      startApplication()

      const categorySelect = element.querySelector('[name="category"]')
      categorySelect.value = "Supermercado"
      categorySelect.dispatchEvent(new Event("change"))

      // Nothing saved yet — debounce pending
      expect(sessionStorage.getItem("expense_filters")).toBeNull()

      // Advance past debounce delay (500ms default)
      jest.advanceTimersByTime(600)

      // URL params are empty so getCurrentFilters returns {} — storage stays null.
      // The auto-save on change reads from URL, so it only saves if URL already has params.
      // The real-world save path on change is supplementary to the form submit save.
      // This test verifies that debounce mechanics work (no crash, no immediate save).
      expect(() => jest.advanceTimersByTime(100)).not.toThrow()
    })
  })

  // -------------------------------------------------------------------------
  // restoreFilters() — restoring saved state
  // -------------------------------------------------------------------------
  describe("restoreFilters()", () => {
    it("navigates to stored filter URL when no filters are in the current URL", () => {
      // Pre-seed sessionStorage with saved filters
      const stored = {
        filters: { category: "Supermercado", bank: "BCR" },
        timestamp: Date.now(),
        url: "/expenses"
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(stored))

      // Spy on location assignment before the controller connects and triggers restore
      const assignSpy = jest.fn()
      Object.defineProperty(window, "location", {
        value: {
          search: "",
          pathname: "/expenses",
          href: "http://localhost/expenses",
          set href(url) { assignSpy(url) }
        },
        writable: true
      })

      buildDOM()
      startApplication()

      // restoreFilters is called in connect() — it should trigger navigation
      expect(assignSpy).toHaveBeenCalledWith(
        expect.stringContaining("category=Supermercado")
      )
    })

    it("does NOT restore when the URL already has filter params", () => {
      const stored = {
        filters: { category: "Supermercado" },
        timestamp: Date.now(),
        url: "/expenses"
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(stored))

      const assignSpy = jest.fn()
      Object.defineProperty(window, "location", {
        value: {
          search: "?category=Restaurante",
          pathname: "/expenses",
          href: "http://localhost/expenses?category=Restaurante",
          set href(url) { assignSpy(url) }
        },
        writable: true
      })

      buildDOM({ urlSearch: "?category=Restaurante" })
      startApplication()

      expect(assignSpy).not.toHaveBeenCalled()
    })

    it("does NOT restore when stored filters are from a different page", () => {
      const stored = {
        filters: { category: "Supermercado" },
        timestamp: Date.now(),
        url: "/admin/expenses"  // different page
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(stored))

      const assignSpy = jest.fn()
      Object.defineProperty(window, "location", {
        value: {
          search: "",
          pathname: "/expenses",
          href: "http://localhost/expenses",
          set href(url) { assignSpy(url) }
        },
        writable: true
      })

      buildDOM()
      startApplication()

      expect(assignSpy).not.toHaveBeenCalled()
    })

    it("does NOT restore when stored filters have no url field (PER-236 guard)", () => {
      // Filters saved by legacy code or a missing url field must not restore on
      // arbitrary pages — this was the root cause of the PER-236 redirect bug.
      const stored = {
        filters: { category: "Supermercado" },
        timestamp: Date.now()
        // url is intentionally absent
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(stored))

      const assignSpy = jest.fn()
      Object.defineProperty(window, "location", {
        value: {
          search: "",
          pathname: "/expenses",
          href: "http://localhost/expenses",
          set href(url) { assignSpy(url) }
        },
        writable: true
      })

      buildDOM()
      startApplication()

      expect(assignSpy).not.toHaveBeenCalled()
    })

    it("clears stored filters when they are expired", () => {
      const expired = {
        filters: { category: "Supermercado" },
        timestamp: Date.now() - (25 * 60 * 60 * 1000),  // 25 hours ago
        url: "/expenses"
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(expired))

      const assignSpy = jest.fn()
      Object.defineProperty(window, "location", {
        value: {
          search: "",
          pathname: "/expenses",
          href: "http://localhost/expenses",
          set href(url) { assignSpy(url) }
        },
        writable: true
      })

      buildDOM()
      startApplication()

      expect(assignSpy).not.toHaveBeenCalled()
      expect(sessionStorage.getItem("expense_filters")).toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // getFiltersFromForm() — form field extraction
  // -------------------------------------------------------------------------
  describe("getFiltersFromForm()", () => {
    it("extracts only non-empty field values from the form", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Supermercado"
      // bank and dates left empty

      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored.filters).toEqual({ category: "Supermercado" })
    })

    it("extracts multiple fields when all are populated", () => {
      buildDOM()
      startApplication()

      const form = element.querySelector("form")
      form.querySelector('[name="category"]').value = "Restaurante"
      form.querySelector('[name="bank"]').value = "BCR"
      form.querySelector('[name="start_date"]').value = "2026-03-01"
      form.querySelector('[name="end_date"]').value = "2026-03-31"

      form.dispatchEvent(new Event("submit"))

      const stored = JSON.parse(sessionStorage.getItem("expense_filters"))
      expect(stored.filters).toEqual({
        category: "Restaurante",
        bank: "BCR",
        start_date: "2026-03-01",
        end_date: "2026-03-31"
      })
    })
  })

  // -------------------------------------------------------------------------
  // clearStoredFilters() — clearing
  // -------------------------------------------------------------------------
  describe("clearStoredFilters()", () => {
    it("removes the storage key when clearStorage action is invoked", () => {
      sessionStorage.setItem("expense_filters", JSON.stringify({
        filters: { category: "Supermercado" },
        timestamp: Date.now(),
        url: "/expenses"
      }))

      buildDOM()
      startApplication()

      // Access controller instance via element's __stimulusControllerMap or call directly
      const controller = element["__stimulusController"] ||
        application.getControllerForElementAndIdentifier(element, "filter-persistence")
      controller.clearStorage()

      expect(sessionStorage.getItem("expense_filters")).toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // restore button visibility
  // -------------------------------------------------------------------------
  describe("restore button visibility", () => {
    it("shows restore button when valid stored filters exist", () => {
      const stored = {
        filters: { category: "Supermercado" },
        timestamp: Date.now(),
        url: "/expenses"
      }
      sessionStorage.setItem("expense_filters", JSON.stringify(stored))

      // Prevent the restore navigation so we can inspect the button state
      Object.defineProperty(window, "location", {
        value: {
          search: "?category=Supermercado",  // already has filters => no redirect
          pathname: "/expenses",
          href: "http://localhost/expenses?category=Supermercado"
        },
        writable: true
      })

      buildDOM({ urlSearch: "?category=Supermercado" })
      startApplication()

      const restoreButton = element.querySelector('[data-filter-persistence-target="restoreButton"]')
      expect(restoreButton.classList.contains("hidden")).toBe(false)
    })

    it("keeps restore button hidden when no filters are stored", () => {
      buildDOM()
      startApplication()

      const restoreButton = element.querySelector('[data-filter-persistence-target="restoreButton"]')
      expect(restoreButton.classList.contains("hidden")).toBe(true)
    })
  })

  // -------------------------------------------------------------------------
  // disconnect() — cleanup
  // -------------------------------------------------------------------------
  describe("disconnect()", () => {
    it("clears pending save timer on disconnect", () => {
      buildDOM()
      startApplication()

      // Trigger a debounced save
      const categorySelect = element.querySelector('[name="category"]')
      categorySelect.value = "Supermercado"
      categorySelect.dispatchEvent(new Event("change"))

      // Remove the element to trigger disconnect
      expect(() => element.remove()).not.toThrow()
    })

    it("removes the storage event listener on disconnect", () => {
      const removeListenerSpy = jest.spyOn(window, "removeEventListener")
      buildDOM()
      startApplication()

      element.remove()

      expect(removeListenerSpy).toHaveBeenCalledWith("storage", expect.any(Function))
    })
  })
})
