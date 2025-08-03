class SyncService
  class SyncError < StandardError; end

  def initialize
  end

  def sync_emails(email_account_id: nil)
    if email_account_id.present?
      sync_specific_account(email_account_id)
    else
      sync_all_accounts
    end
  end

  private

  def sync_specific_account(email_account_id)
    email_account = EmailAccount.find_by(id: email_account_id)

    if email_account.nil?
      raise SyncError, "Cuenta de correo no encontrada."
    end

    unless email_account.active?
      raise SyncError, "La cuenta de correo está inactiva."
    end

    ProcessEmailsJob.perform_later(email_account.id)

    {
      success: true,
      message: "Sincronización iniciada para #{email_account.email}. Los nuevos gastos aparecerán en unos momentos.",
      email_account: email_account
    }
  end

  def sync_all_accounts
    active_accounts = EmailAccount.active.count

    if active_accounts == 0
      raise SyncError, "No hay cuentas de correo activas configuradas."
    end

    ProcessEmailsJob.perform_later

    {
      success: true,
      message: "Sincronización iniciada para #{active_accounts} cuenta#{'s' if active_accounts != 1} de correo. Los nuevos gastos aparecerán en unos momentos.",
      account_count: active_accounts
    }
  end
end
