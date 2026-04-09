# frozen_string_literal: true

module PatternsHelper
  PATTERN_TYPE_TRANSLATIONS = {
    "merchant" => "Comercio",
    "keyword" => "Palabra clave",
    "description" => "Descripción",
    "amount_range" => "Rango de monto",
    "regex" => "Regex",
    "time" => "Hora"
  }.freeze

  def pattern_type_options
    [
      [ "Nombre de comercio", "merchant" ],
      [ "Palabra clave", "keyword" ],
      [ "Descripción", "description" ],
      [ "Rango de monto", "amount_range" ],
      [ "Expresión regular", "regex" ],
      [ "Patrón de hora", "time" ]
    ]
  end

  def pattern_type_filter_options
    [
      [ "Todos los tipos", "" ],
      [ "Comercio", "merchant" ],
      [ "Palabra clave", "keyword" ],
      [ "Descripción", "description" ],
      [ "Rango de monto", "amount_range" ],
      [ "Regex", "regex" ],
      [ "Hora", "time" ]
    ]
  end

  def pattern_status_filter_options
    [
      [ "Todos los estados", "" ],
      [ "Activo", "active" ],
      [ "Inactivo", "inactive" ],
      [ "Creado por usuario", "user_created" ],
      [ "Creado por sistema", "system_created" ],
      [ "Alta confianza", "high_confidence" ],
      [ "Exitoso", "successful" ],
      [ "Uso frecuente", "frequently_used" ]
    ]
  end
end
