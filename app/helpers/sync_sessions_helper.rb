# frozen_string_literal: true

module SyncSessionsHelper
  def sync_widget_messages
    {
      connection: I18n.t("errors.connection"),
      auth: I18n.t("errors.auth"),
      server: I18n.t("errors.server"),
      recovery: I18n.t("errors.recovery"),
      sync: I18n.t("errors.sync"),
      generic: I18n.t("errors.generic"),
      suggestions: I18n.t("errors.suggestions"),
      actions: I18n.t("actions"),
      status: I18n.t("sync.status")
    }
  end
end
