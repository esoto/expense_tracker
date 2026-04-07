module Services
  module EmailProcessing
    # Shared date parsing logic used by both Strategies::Regex and ParsingRule.
    # Handles Spanish month abbreviations and multiple date formats common in
    # Costa Rican bank email notifications.
    module DateParsingHelper
      # Ordered by likelihood of appearance in Costa Rican bank emails.
      DATE_FORMATS = [
        "%d/%m/%Y",          # 03/08/2024       — most common CR format
        "%d-%m-%Y",          # 03-08-2024
        "%b %d, %Y, %H:%M", # Aug 1, 2025, 14:16 — BAC format with time
        "%b %d, %Y",         # Aug 1, 2025        — BAC format without time
        "%d/%m/%Y %H:%M",    # 03/08/2024 14:30
        "%d-%m-%Y %H:%M",    # 03-08-2024 09:15
        "%Y-%m-%d",          # 2025-08-01        — ISO 8601
        "%d de %B de %Y",    # 3 de Agosto de 2024
        "%d %B %Y"           # 03 Agosto 2024
      ].freeze

      SPANISH_MONTHS = {
        "Ene" => "Jan", "Feb" => "Feb", "Mar" => "Mar", "Abr" => "Apr",
        "May" => "May", "Jun" => "Jun", "Jul" => "Jul", "Ago" => "Aug",
        "Sep" => "Sep", "Oct" => "Oct", "Nov" => "Nov", "Dic" => "Dec"
      }.freeze

      def parse_date(date_str)
        date_str = date_str.strip
        date_str = translate_spanish_months(date_str)

        DATE_FORMATS.each do |format|
          return Date.strptime(date_str, format)
        rescue ArgumentError
          next
        end

        Chronic.parse(date_str)&.to_date
      rescue StandardError
        nil
      end

      private

      def translate_spanish_months(date_str)
        SPANISH_MONTHS.reduce(date_str) do |str, (spanish, english)|
          str.gsub(spanish, english)
        end
      end
    end
  end
end
