module EmailAccountsHelper
  def bank_options
    [ "BAC", "Banco Nacional", "BCR", "Scotiabank", "Banco Popular", "Davivienda" ]
  end

  def email_provider_options
    [
      [ "Gmail", "gmail" ],
      [ "Outlook/Hotmail", "outlook" ],
      [ "Yahoo", "yahoo" ],
      [ "Personalizado", "custom" ]
    ]
  end
end
