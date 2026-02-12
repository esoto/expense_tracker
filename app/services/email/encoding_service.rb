# frozen_string_literal: true

module Services::Email
  class EncodingService
    COMMON_ENCODINGS = %w[UTF-8 ISO-8859-1 Windows-1252 UTF-16 ASCII].freeze

    class << self
      def safe_decode(text, options = {})
        return nil if text.nil?

        text = text.dup
        original_encoding = text.encoding

        # Handle quoted-printable encoding first
        if options[:quoted_printable]
          text = decode_quoted_printable(text)
        end

        # Handle base64 encoding
        if options[:base64]
          text = Base64.decode64(text)
        end

        # Detect and convert encoding
        result = detect_and_convert(text, original_encoding)

        # Apply final scrubbing
        result.scrub(options[:replace_char] || "?")
      rescue => e
        Rails.logger.warn "[EncodingService] Failed to decode: #{e.message}"
        fallback_decode(text)
      end

      private

      def detect_and_convert(text, original_encoding)
        # If already valid UTF-8, return it
        if text.encoding == Encoding::UTF_8 && text.valid_encoding?
          return text
        end

        # Try to detect encoding using simple heuristics
        detected = detect_encoding(text)
        if detected && detected != "UTF-8"
          return text.force_encoding(detected).encode("UTF-8",
            invalid: :replace,
            undef: :replace,
            replace: "?"
          )
        end

        # Fallback to trying common encodings
        COMMON_ENCODINGS.each do |encoding|
          begin
            text.force_encoding(encoding)
            if text.valid_encoding?
              return text.encode("UTF-8", invalid: :replace, undef: :replace)
            end
          rescue
            next
          end
        end

        # Last resort
        text.force_encoding("UTF-8").scrub("?")
      end

      def decode_quoted_printable(text)
        text.gsub(/=\r?\n/, "")
            .gsub(/=([0-9A-F]{2})/i) { [ $1 ].pack("H*") }
      end

      def detect_encoding(text)
        # Check for BOM markers
        return "UTF-16LE" if text.start_with?("\xFF\xFE")
        return "UTF-16BE" if text.start_with?("\xFE\xFF")
        return "UTF-8" if text.start_with?("\xEF\xBB\xBF")

        # Check for common patterns
        if text.include?("\xC3") || text.include?("\xC2")
          "UTF-8"
        elsif text.bytes.any? { |b| b > 127 && b < 160 }
          "Windows-1252"
        else
          "ISO-8859-1"
        end
      end

      def fallback_decode(text)
        return "" if text.nil?

        text.to_s.encode("UTF-8",
          invalid: :replace,
          undef: :replace,
          replace: "?"
        )
      rescue => e
        Rails.logger.error "[EncodingService] Fallback decode failed: #{e.message}"
        # Force UTF-8 and scrub as last resort
        text.to_s.force_encoding("UTF-8").scrub("?")
      rescue
        # Absolute fallback - return empty string rather than crash
        Rails.logger.error "[EncodingService] Complete encoding failure, returning empty string"
        ""
      end
    end
  end
end
