require "rails_helper"

# PER-119: Verify that key I18n translation keys exist and return the correct
# Spanish strings. These tests ensure that migrated strings are not accidentally
# deleted from the locale file and that the t() calls in views/controllers will
# resolve correctly at runtime.
RSpec.describe "I18n translations (PER-119)", unit: true do
  before do
    I18n.locale = :es
  end

  after do
    I18n.locale = I18n.default_locale
  end

  # -----------------------------------------------------------------------
  # Navigation labels
  # -----------------------------------------------------------------------
  describe "Navigation translations" do
    it "provides a dashboard nav label" do
      expect(I18n.t("nav.dashboard")).to eq("Dashboard")
    end

    it "provides an expenses nav label" do
      expect(I18n.t("nav.expenses")).to eq("Gastos")
    end

    it "provides a categorize nav label" do
      expect(I18n.t("nav.categorize")).to eq("Categorizar")
    end

    it "provides an analytics nav label" do
      expect(I18n.t("nav.analytics")).to eq("Analíticas")
    end

    it "provides an accounts nav label" do
      expect(I18n.t("nav.accounts")).to eq("Cuentas")
    end

    it "provides a sync nav label" do
      expect(I18n.t("nav.sync")).to eq("Sincronización")
    end

    it "provides a budgets nav label" do
      expect(I18n.t("nav.budgets")).to eq("Presupuestos")
    end

    it "provides a categories nav label" do
      expect(I18n.t("nav.categories")).to eq("Categorías")
    end

    it "provides admin nav labels" do
      expect(I18n.t("admin.nav.patterns")).to eq("Patrones")
      expect(I18n.t("admin.nav.composite_patterns")).to eq("Patrones Compuestos")
      expect(I18n.t("admin.nav.analytics")).to eq("Analíticas")
      expect(I18n.t("admin.nav.sync_performance")).to eq("Rendimiento Sync")
      expect(I18n.t("admin.nav.back_to_app")).to eq("← Volver a la App")
      expect(I18n.t("admin.nav.logout")).to eq("Cerrar Sesión")
    end

    it "provides a new expense nav label" do
      expect(I18n.t("nav.new_expense")).to eq("Nuevo Gasto")
    end
  end

  # -----------------------------------------------------------------------
  # Page titles
  # -----------------------------------------------------------------------
  describe "Expense page title translations" do
    it "provides the index page title" do
      expect(I18n.t("expenses.titles.index")).to eq("Gastos - Expense Tracker")
    end

    it "provides the dashboard page title" do
      expect(I18n.t("expenses.titles.dashboard")).to eq("Dashboard - Expense Tracker")
    end

    it "provides the new expense page title" do
      expect(I18n.t("expenses.titles.new")).to eq("Nuevo Gasto - Expense Tracker")
    end

    it "provides the edit expense page title with interpolation" do
      expect(I18n.t("expenses.titles.edit", name: "AMPM")).to eq("Editar AMPM - Expense Tracker")
    end

    it "provides the show expense page title with interpolation" do
      expect(I18n.t("expenses.titles.show", name: "AMPM")).to eq("AMPM - Expense Tracker")
    end

    it "provides the show-no-merchant page title" do
      expect(I18n.t("expenses.titles.show_no_merchant")).to eq("Sin comercio - Expense Tracker")
    end
  end

  # -----------------------------------------------------------------------
  # Common button labels
  # -----------------------------------------------------------------------
  describe "Common action translations" do
    it "provides cancel label" do
      expect(I18n.t("common.cancel")).to eq("Cancelar")
    end

    it "provides delete label" do
      expect(I18n.t("common.delete")).to eq("Eliminar")
    end

    it "provides edit label" do
      expect(I18n.t("common.edit")).to eq("Editar")
    end

    it "provides back label" do
      expect(I18n.t("common.back")).to eq("Volver")
    end

    it "provides filter label" do
      expect(I18n.t("common.filter")).to eq("Filtrar")
    end

    it "provides view label" do
      expect(I18n.t("common.view")).to eq("Ver")
    end

    it "provides are_you_sure confirmation text" do
      expect(I18n.t("common.are_you_sure")).to eq("¿Estás seguro?")
    end
  end

  # -----------------------------------------------------------------------
  # Flash messages — expenses
  # -----------------------------------------------------------------------
  describe "Expense flash message translations" do
    it "provides the created flash" do
      expect(I18n.t("expenses.flash.created")).to eq("Gasto creado exitosamente.")
    end

    it "provides the updated flash" do
      expect(I18n.t("expenses.flash.updated")).to eq("Gasto actualizado exitosamente.")
    end

    it "provides the deleted flash" do
      expect(I18n.t("expenses.flash.deleted")).to eq("Gasto eliminado. Puedes deshacer esta acción.")
    end

    it "provides the delete_error flash" do
      expect(I18n.t("expenses.flash.delete_error")).to eq("Error al eliminar el gasto. Por favor, inténtalo de nuevo.")
    end

    it "provides the not_found flash" do
      expect(I18n.t("expenses.flash.not_found")).to eq("Gasto no encontrado o no tienes permiso para verlo.")
    end

    it "provides the not_authorized flash" do
      expect(I18n.t("expenses.flash.not_authorized")).to eq("No tienes permiso para modificar este gasto.")
    end

    it "provides the category_updated flash" do
      expect(I18n.t("expenses.flash.category_updated")).to eq("Categoría actualizada correctamente")
    end
  end

  # -----------------------------------------------------------------------
  # Flash messages — email accounts
  # -----------------------------------------------------------------------
  describe "Email account flash message translations" do
    it "provides the created flash" do
      expect(I18n.t("email_accounts.flash.created")).to eq("Cuenta de correo creada exitosamente.")
    end

    it "provides the updated flash" do
      expect(I18n.t("email_accounts.flash.updated")).to eq("Cuenta de correo actualizada exitosamente.")
    end

    it "provides the deleted flash" do
      expect(I18n.t("email_accounts.flash.deleted")).to eq("Cuenta de correo eliminada exitosamente.")
    end
  end

  # -----------------------------------------------------------------------
  # Flash messages — sync sessions
  # -----------------------------------------------------------------------
  describe "Sync session flash message translations" do
    it "provides the started flash" do
      expect(I18n.t("sync_sessions.flash.started")).to eq("Sincronización iniciada exitosamente")
    end

    it "provides the cancelled flash" do
      expect(I18n.t("sync_sessions.flash.cancelled")).to eq("Sincronización cancelada exitosamente")
    end

    it "provides the cancel_error flash" do
      expect(I18n.t("sync_sessions.flash.cancel_error")).to eq("Error al cancelar la sincronización")
    end

    it "provides the not_found flash" do
      expect(I18n.t("sync_sessions.flash.not_found")).to eq("Sincronización no encontrada")
    end
  end

  # -----------------------------------------------------------------------
  # Expense form actions
  # -----------------------------------------------------------------------
  describe "Expense form action translations" do
    it "provides the create action label" do
      expect(I18n.t("expenses.actions.create")).to eq("Crear Gasto")
    end

    it "provides the update action label" do
      expect(I18n.t("expenses.actions.update")).to eq("Actualizar Gasto")
    end

    it "provides the delete_confirm text" do
      expect(I18n.t("expenses.actions.delete_confirm")).to eq("¿Estás seguro de que quieres eliminar este gasto?")
    end
  end

  # -----------------------------------------------------------------------
  # Guard: no translation key returns a missing-translation placeholder
  # -----------------------------------------------------------------------
  describe "Translation key completeness guard" do
    let(:critical_keys) do
      %w[
        nav.dashboard
        nav.expenses
        nav.new_expense
        expenses.titles.index
        expenses.titles.dashboard
        expenses.flash.created
        expenses.flash.updated
        expenses.flash.deleted
        email_accounts.flash.created
        sync_sessions.flash.started
        common.cancel
        common.delete
        common.edit
        common.back
        common.filter
      ]
    end

    it "does not have any missing-translation placeholders for critical keys" do
      missing = critical_keys.select do |key|
        I18n.t(key).start_with?("translation missing:")
      end
      expect(missing).to be_empty,
        "Missing translations for: #{missing.join(', ')}"
    end
  end
end
