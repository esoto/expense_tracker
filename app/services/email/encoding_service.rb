# frozen_string_literal: true

module Services::Email
  class EncodingService
    COMMON_ENCODINGS = %w[UTF-8 ISO-8859-1 Windows-1252 UTF-16 ASCII].freeze

    class << self
      def safe_decode(text, options = {})
        return nil if text.nil?

        text = text.dup
        replacement = options[:replace_char] || "?"

        # Handle quoted-printable encoding first
        if options[:quoted_printable]
          text = decode_quoted_printable(text)
        end

        # Handle base64 encoding
        if options[:base64]
          text = Base64.decode64(text)
        end

        # Detect and convert encoding
        result = detect_and_convert(text, replacement)

        # Apply final scrubbing
        result.scrub(replacement)
      rescue => e
        Rails.logger.warn "[EncodingService] Failed to decode: #{e.message}"
        fallback_decode(text, replacement)
      end

      private

      def detect_and_convert(text, replacement)
        # If already valid UTF-8, return it
        if text.encoding == Encoding::UTF_8 && text.valid_encoding?
          return text
        end

        # Try to detect encoding using byte-level heuristics
        detected = detect_encoding(text)

        if detected == "UTF-8"
          # Force encoding label and scrub invalid sequences,
          # preserving valid multi-byte characters like "café"
          return text.dup.force_encoding(Encoding::UTF_8).scrub(replacement)
        end

        if detected
          converted = text.dup.force_encoding(detected)
          if converted.valid_encoding?
            return converted.encode("UTF-8", invalid: :replace, undef: :replace, replace: replacement)
          end
        end

        # Fallback to trying common encodings
        COMMON_ENCODINGS.each do |encoding|
          begin
            candidate = text.dup.force_encoding(encoding)
            if candidate.valid_encoding?
              return candidate.encode("UTF-8", invalid: :replace, undef: :replace, replace: replacement)
            end
          rescue
            next
          end
        end

        # Last resort
        text.force_encoding("UTF-8").scrub(replacement)
      end

      def decode_quoted_printable(text)
        # Work in binary to avoid encoding incompatibility when inserting
        # decoded bytes (e.g. \xC3\xB1) into a UTF-8 string.
        binary = text.dup.force_encoding(Encoding::ASCII_8BIT)
        decoded = binary.gsub(/=\r?\n/n, "".b)
                        .gsub(/=([0-9A-Fa-f]{2})/n) { [ $1 ].pack("H*") }
        decoded.force_encoding(Encoding::UTF_8)
      end

      def detect_encoding(text)
        raw = text.b

        # Check for BOM markers
        return "UTF-16LE" if raw.start_with?("\xFF\xFE".b)
        return "UTF-16BE" if raw.start_with?("\xFE\xFF".b)
        return "UTF-8" if raw.start_with?("\xEF\xBB\xBF".b)

        # Check for common UTF-8 multi-byte lead bytes
        if raw.include?("\xC3".b) || raw.include?("\xC2".b)
          "UTF-8"
        elsif raw.bytes.any? { |b| b > 127 && b < 160 }
          "Windows-1252"
        else
          "ISO-8859-1"
        end
      end

      def fallback_decode(text, replacement = "?")
        return "" if text.nil?

        text.to_s.encode("UTF-8",
          invalid: :replace,
          undef: :replace,
          replace: replacement
        )
      rescue => e
        Rails.logger.error "[EncodingService] Fallback decode failed: #{e.message}"
        text.to_s.force_encoding("UTF-8").scrub(replacement)
      rescue
        Rails.logger.error "[EncodingService] Complete encoding failure, returning empty string"
        ""
      end
    end
  end
end
