# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Email::EncodingService do
  describe '.safe_decode' do
    context 'with valid UTF-8 text' do
      it 'returns the text unchanged' do
        text = "Valid UTF-8 text with accents: café, niño"
        result = described_class.safe_decode(text)

        expect(result).to eq(text)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with nil input' do
      it 'returns nil' do
        expect(described_class.safe_decode(nil)).to be_nil
      end
    end

    context 'with empty string' do
      it 'returns empty string in UTF-8' do
        result = described_class.safe_decode("")

        expect(result).to eq("")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with ISO-8859-1 encoded text' do
      it 'converts to UTF-8 properly' do
        # Create ISO-8859-1 encoded text
        original = "Café with special chars: ñáéíóú"
        iso_text = original.encode('ISO-8859-1')

        result = described_class.safe_decode(iso_text)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq(original)
      end
    end

    context 'with Windows-1252 encoded text' do
      it 'converts to UTF-8 properly' do
        # Create Windows-1252 encoded text with smart quotes
        original = "Hello \"world\" with smart quotes"
        win_text = original.encode('Windows-1252')

        result = described_class.safe_decode(win_text)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq(original)
      end
    end

    context 'with binary data containing invalid UTF-8 sequences' do
      it 'handles invalid sequences gracefully' do
        # Use bytes that contain UTF-8 lead bytes (\xC3) followed by invalid
        # continuation bytes, so the detector identifies UTF-8 and scrubs them.
        invalid_bytes = "Hello \xC3\x28 world \xC2".dup
        text = invalid_bytes.force_encoding('UTF-8')

        result = described_class.safe_decode(text)

        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
        expect(result).to include('Hello')
        expect(result).to include('world')
      end
    end

    context 'with quoted-printable encoding' do
      it 'decodes quoted-printable sequences' do
        qp_text = "Espa=C3=B1ol with =C3=A1ccents"
        result = described_class.safe_decode(qp_text, quoted_printable: true)

        expect(result).to eq("Español with áccents")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it 'handles soft line breaks in quoted-printable' do
        qp_text = "Long line that breaks=\r\nhere"
        result = described_class.safe_decode(qp_text, quoted_printable: true)

        expect(result).to eq("Long line that breakshere")
      end
    end

    context 'with base64 encoding' do
      it 'decodes base64 content' do
        original = "Hello world with UTF-8: café"
        base64_text = Base64.encode64(original)

        result = described_class.safe_decode(base64_text, base64: true)

        expect(result).to eq(original)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context 'with UTF-16 BOM markers' do
      it 'detects UTF-16LE BOM' do
        text = "\xFF\xFEH\x00e\x00l\x00l\x00o\x00"
        result = described_class.safe_decode(text)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include('Hello')
      end

      it 'detects UTF-16BE BOM' do
        text = "\xFE\xFF\x00H\x00e\x00l\x00l\x00o"
        result = described_class.safe_decode(text)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include('Hello')
      end

      it 'detects UTF-8 BOM' do
        text = "\xEF\xBB\xBFHello UTF-8 with BOM"
        result = described_class.safe_decode(text)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include('Hello UTF-8 with BOM')
      end
    end

    context 'with custom replacement character' do
      it 'uses custom replacement character for invalid sequences' do
        # Use incomplete UTF-8 lead bytes so detector identifies UTF-8
        # and scrubs with the custom replacement character.
        invalid_text = "Valid text \xC3 incomplete \xC2 sequences"
        result = described_class.safe_decode(invalid_text, replace_char: '■')

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
        expect(result).to include('■')
        expect(result).to include('Valid text')
      end
    end

    context 'with completely corrupted data' do
      it 'falls back gracefully when main decode path fails' do
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:error)

        corrupted = "\x00\x01\x02\x03\xC3\x28\xFD\xFC"

        # Force the main decode path to fail, triggering fallback
        allow(described_class).to receive(:detect_and_convert)
          .and_raise(StandardError, "Simulated failure")

        result = described_class.safe_decode(corrupted)

        # fallback_decode should produce a valid UTF-8 string
        expect(result).to be_a(String)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
      end
    end

    context 'edge cases' do
      it 'handles very large strings efficiently' do
        large_text = "A" * 10_000 + "café" + "B" * 10_000
        iso_large = large_text.encode('ISO-8859-1')

        result = described_class.safe_decode(iso_large)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include('café')
        expect(result.length).to eq(large_text.length)
      end

      it 'handles strings with mixed valid and invalid sequences' do
        mixed = "Valid: café " + "\xFF\xFE" + " More valid: niño"
        result = described_class.safe_decode(mixed)

        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result.valid_encoding?).to be true
        expect(result).to include('café')
        expect(result).to include('niño')
      end

      it 'preserves empty strings correctly' do
        empty_iso = "".encode('ISO-8859-1')
        result = described_class.safe_decode(empty_iso)

        expect(result).to eq("")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end
  end
end
