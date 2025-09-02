FactoryBot.define do
  factory :parsing_rule do
    bank_name { "BAC" }
    amount_pattern { 'Monto:[\\s]*CRC[\\s]*([\\d,]+\\.\\d{2})' }
    date_pattern { 'Fecha:[\\s]*(.+?)(?=\\n|$)' }
    merchant_pattern { 'Comercio:[\\s]*([A-Z\\s]+?)(?=\\s*$|\\n)' }
    description_pattern { 'Tipo de Transacci[oó]n:[\\s]*([A-Z]+)' }
    email_pattern { '(?:transacci[oó]n|notificaci[oó]n).*(?:BAC|PTA)' }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :bac do
      bank_name { "BAC" }
      amount_pattern { '(?:Monto)[: ]*(?:₡|USD|CRC)?[: ]*([\\d,]+(?:\\.\\d{2})?)' }
      date_pattern { 'Fecha:\\s*(.+?)(?=\\n|$)' }
      merchant_pattern { '(?:Comercio)[: ]*([A-Z0-9 .]+?)(?:\\s*$|\\n| *Ciudad| *Fecha| *VISA| *MASTER)' }
      description_pattern { '(?:Tipo de Transacci[oó]n|Descripci[oó]n)[:\\s]*(.+?)(?:\\s*$|\\n)' }
      email_pattern { '(?:transacci[oó]n|notificaci[oó]n).*(?:BAC|PTA)' }
    end

    trait :bcr do
      bank_name { "BCR" }
      amount_pattern { '(?:₡|colones?|CRC)[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)' }
      date_pattern { '(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})' }
      merchant_pattern { '(?:comercio|merchant|establecimiento)[:\\s]+(.*?)(?:\\n|$)' }
      description_pattern { '(?:descripcion|concepto)[:\\s]+(.*?)(?:\\n|$)' }
      email_pattern { '(?:transacci[oó]n|compra|pago|cargo).*BCR' }
    end

    trait :scotiabank do
      bank_name { "Scotiabank" }
      amount_pattern { '(?:Amount|Monto)[:\\s]*(?:\\$|USD|₡|CRC)?[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)' }
      date_pattern { '(?:Date|Fecha)[:\\s]*([A-Za-z]+\\s+\\d{1,2},?\\s+\\d{4}|\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})' }
      merchant_pattern { '(?:Merchant|merchant|comercio)[:\\s]+(.*?)(?:\\n|$)' }
      description_pattern { '(?:description|descripcion)[:\\s]+(.*?)(?:\\n|$)' }
      email_pattern { '(?:transacci[oó]n|transaction|alert|purchase).*Scotia' }
    end

    trait :banco_nacional do
      bank_name { "Banco Nacional" }
      amount_pattern { '(?:₡|colones)[\\s]*(\\d{1,3}(?:[,.]\\d{3})*(?:[,.]\\d{2})?)' }
      date_pattern { '(\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4})' }
      merchant_pattern { '(?:establecimiento|comercio)[:\\s]+(.*?)(?:\\n|$)' }
      description_pattern { '(?:detalle|concepto)[:\\s]+(.*?)(?:\\n|$)' }
      email_pattern { '(?:notificaci[oó]n|transacci[oó]n).*(?:Banco Nacional|BNCR)' }
    end

    trait :simple do
      amount_pattern { 'Monto:[\\s]*([\\d,]+\\.\\d{2})' }
      date_pattern { 'Fecha:[\\s]*(.+)' }
      merchant_pattern { 'Comercio:[\\s]*(.+)' }
      description_pattern { 'Tipo:[\\s]*(.+)' }
    end
  end
end
