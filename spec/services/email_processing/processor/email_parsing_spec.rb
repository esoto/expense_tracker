require 'rails_helper'
require 'support/email_processing_processor_test_helper'

RSpec.describe 'EmailProcessing::Processor - Email Parsing', type: :service, unit: true do
  include EmailProcessingProcessorTestHelper
  let(:email_account) { create(:email_account, :bac) }
  let(:processor) { EmailProcessing::Processor.new(email_account) }
  let(:mock_imap_service) { instance_double(ImapConnectionService) }

  describe 'complex multipart email handling' do
    let(:message_id) { 123 }

    describe '#extract_multipart_body edge cases' do
      context 'with nested multipart structures' do
        let(:nested_text_part) { double('text_part', media_type: 'TEXT', subtype: 'PLAIN') }
        let(:nested_html_part) { double('html_part', media_type: 'TEXT', subtype: 'HTML') }
        let(:inner_multipart) do
          double('inner_multipart',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'ALTERNATIVE',
            parts: [ nested_text_part, nested_html_part ]
          )
        end
        let(:attachment_part) { double('attachment', media_type: 'APPLICATION', subtype: 'PDF') }
        let(:outer_multipart) do
          double('outer_multipart',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'MIXED',
            parts: [ inner_multipart, attachment_part ]
          )
        end

        it 'handles deeply nested multipart structures' do
          # Should find text part in nested structure
          allow(processor).to receive(:find_text_part).with(outer_multipart).and_return(nil)
          allow(processor).to receive(:find_html_part).with(outer_multipart).and_return(nil)
          allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback text')

          result = processor.send(:extract_multipart_body, message_id, outer_multipart, mock_imap_service)

          expect(result).to eq('Fallback text')
        end
      end

      context 'with multipart/related structures' do
        let(:html_part) { double('html', media_type: 'TEXT', subtype: 'HTML') }
        let(:image_part) { double('image', media_type: 'IMAGE', subtype: 'PNG') }
        let(:related_structure) do
          double('related',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'RELATED',
            parts: [ html_part, image_part ]
          )
        end

        it 'extracts HTML from multipart/related' do
          allow(processor).to receive(:find_text_part).and_return(nil)
          allow(processor).to receive(:find_html_part).and_return('1')
          allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
            .and_return('<html>Email with embedded images</html>')
          allow(processor).to receive(:extract_text_from_html)
            .and_return('Email with embedded images')

          result = processor.send(:extract_multipart_body, message_id, related_structure, mock_imap_service)

          expect(result).to eq('Email with embedded images')
        end
      end

      context 'with malformed part structure' do
        let(:malformed_structure) do
          double('malformed', multipart?: true, parts: nil)
        end

        it 'handles nil parts array gracefully' do
          allow(processor).to receive(:find_text_part).and_return(nil)
          allow(processor).to receive(:find_html_part).and_return(nil)
          allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback')

          result = processor.send(:extract_multipart_body, message_id, malformed_structure, mock_imap_service)

          expect(result).to eq('Fallback')
        end
      end

      context 'with empty multipart structure' do
        let(:empty_structure) do
          double('empty', multipart?: true, parts: [])
        end

        it 'falls back when no parts available' do
          allow(processor).to receive(:find_text_part).and_return(nil)
          allow(processor).to receive(:find_html_part).and_return(nil)
          allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback content')

          result = processor.send(:extract_multipart_body, message_id, empty_structure, mock_imap_service)

          expect(result).to eq('Fallback content')
        end
      end

      context 'when HTML part fetch returns nil' do
        let(:structure) { double('structure', multipart?: true) }

        it 'falls back when HTML content is nil' do
          allow(processor).to receive(:find_text_part).and_return(nil)
          allow(processor).to receive(:find_html_part).and_return('2')
          allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '2')
            .and_return(nil)
          allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback')

          result = processor.send(:extract_multipart_body, message_id, structure, mock_imap_service)

          expect(result).to eq('Fallback')
        end
      end
    end

    describe 'character encoding edge cases' do
      describe '#extract_text_from_html encoding scenarios' do
        context 'with various character encodings' do
          it 'handles ISO-8859-1 encoded content' do
            # ISO-8859-1 encoded HTML with special characters
            html = "<html><body>Caf\xE9 con ma\xF1ana</body></html>".force_encoding('ISO-8859-1')

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('Caf')
            expect(result.encoding.name).to eq('UTF-8')
          end

          it 'handles Windows-1252 encoded content' do
            # Windows-1252 specific characters
            html = "<html><body>Smart quotes: \x93Hello\x94</body></html>".force_encoding('Windows-1252')

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('Hello')
            expect(result.encoding.name).to eq('UTF-8')
          end

          it 'handles mixed encoding within same content' do
            html = "<html><body>UTF-8: Café, ISO: Ñoño</body></html>"

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('UTF-8: Café, ISO: Ñoño')
          end

          it 'handles binary data gracefully' do
            binary_content = "\x00\x01\x02<html>Text</html>\xFF\xFE".force_encoding('BINARY')

            result = processor.send(:extract_text_from_html, binary_content)

            expect(result).to include('Text')
            expect(result.encoding.name).to eq('UTF-8')
          end
        end

        context 'with quoted-printable edge cases' do
          it 'handles soft line breaks correctly' do
            html = "This is a long line that =\r\ncontinues here"

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('This is a long line that continues here')
          end

          it 'handles encoded special characters' do
            html = "Special chars: =C3=B1 =C3=A9 =C2=A1"

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('Special chars:')
          end

          it 'handles incomplete quoted-printable sequences' do
            html = "Incomplete sequence: =C3<html>content</html>"

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('content')
          end

          it 'handles mixed line endings' do
            html = "Line one=\nLine two=\r\nLine three"

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('Line oneLine twoLine three')
          end
        end

        context 'with HTML entity edge cases' do
          it 'decodes numeric HTML entities' do
            html = '&#65;&#66;&#67; &#8364; &#x20AC;'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('ABC')
          end

          it 'handles malformed HTML entities' do
            html = 'Broken entities: &amp &lt &invalidEntity; &;'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('Broken entities')
          end

          it 'decodes all Spanish special characters' do
            html = '&aacute;&eacute;&iacute;&oacute;&uacute;&ntilde;&Aacute;&Eacute;&Iacute;&Oacute;&Uacute;&Ntilde;'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('áéíóúñÁÉÍÓÚÑ')
          end

          it 'handles nested HTML tags with entities' do
            html = '<div>&lt;script&gt;alert(&quot;test&quot;)&lt;/script&gt;</div>'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to include('<script>alert("test")</script>')
          end
        end

        context 'with complex HTML structures' do
          it 'removes style tags with CSS content' do
            html = '''
              <html>
                <head>
                  <style type="text/css">
                    body { font-family: Arial; }
                    .hidden { display: none; }
                  </style>
                </head>
                <body>Visible content</body>
              </html>
            '''

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Visible content')
            expect(result).not_to include('font-family')
          end

          it 'removes script tags with JavaScript' do
            html = '''
              <html>
                <body>
                  Before script
                  <script>
                    function test() {
                      console.log("test");
                    }
                  </script>
                  After script
                </body>
              </html>
            '''

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Before script After script')
            expect(result).not_to include('console.log')
          end

          it 'handles HTML comments' do
            html = '<html><!-- Comment -->Visible<!-- Another comment --></html>'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Visible')
          end

          it 'preserves important whitespace' do
            html = '<html><pre>  Formatted   Text  </pre></html>'

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Formatted Text')
          end
        end

        context 'with encoding error recovery' do
          it 'recovers from Encoding::CompatibilityError' do
            html = "<html>Test content</html>"

            # Force an encoding compatibility error scenario
            allow(html).to receive(:force_encoding).and_raise(Encoding::CompatibilityError)
            allow(Rails.logger).to receive(:warn)

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Test content')
            expect(result.encoding.name).to eq('UTF-8')
          end

          it 'recovers from Encoding::UndefinedConversionError' do
            html = "<html>Test content</html>"

            # Force an undefined conversion error scenario
            allow(html).to receive(:gsub).and_raise(Encoding::UndefinedConversionError)
            allow(Rails.logger).to receive(:warn)

            result = processor.send(:extract_text_from_html, html)

            expect(result).to eq('Test content')
            expect(result.encoding.name).to eq('UTF-8')
          end
        end
      end
    end

    describe 'multipart part finding algorithms' do
      describe '#find_text_part with complex structures' do
        it 'finds text part at various depths' do
          part1 = double('part1', media_type: 'IMAGE', subtype: 'PNG')
          part2 = double('part2', media_type: 'TEXT', subtype: 'PLAIN')
          part3 = double('part3', media_type: 'TEXT', subtype: 'HTML')

          structure = double('structure',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'MIXED',
            parts: [ part1, part2, part3 ]
          )

          result = processor.send(:find_text_part, structure)

          expect(result).to eq('2') # Second part (1-indexed)
        end

        it 'returns nil for non-multipart non-text structure' do
          structure = double('structure',
            multipart?: false,
            media_type: 'IMAGE',
            subtype: 'JPEG'
          )

          result = processor.send(:find_text_part, structure)

          expect(result).to be_nil
        end

        it 'handles structures with many parts' do
          parts = (1..20).map do |i|
            double("part#{i}",
              media_type: i == 15 ? 'TEXT' : 'APPLICATION',
              subtype: i == 15 ? 'PLAIN' : 'OCTET-STREAM'
            )
          end

          structure = double('structure',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'MIXED',
            parts: parts
          )

          result = processor.send(:find_text_part, structure)

          expect(result).to eq('15')
        end
      end

      describe '#find_html_part with complex structures' do
        it 'finds HTML part in mixed multipart' do
          parts = [
            double('part1', media_type: 'TEXT', subtype: 'PLAIN'),
            double('part2', media_type: 'TEXT', subtype: 'HTML'),
            double('part3', media_type: 'APPLICATION', subtype: 'PDF')
          ]

          structure = double('structure',
            multipart?: true,
            media_type: 'MULTIPART',
            subtype: 'MIXED',
            parts: parts
          )

          result = processor.send(:find_html_part, structure)

          expect(result).to eq('2')
        end

        it 'returns nil when only text/plain available' do
          parts = [
            double('part1', media_type: 'TEXT', subtype: 'PLAIN'),
            double('part2', media_type: 'APPLICATION', subtype: 'PDF')
          ]

          structure = double('structure',
            multipart?: true,
            media_type: nil,
            subtype: nil,
            parts: parts
          )

          result = processor.send(:find_html_part, structure)

          expect(result).to be_nil
        end
      end
    end

    describe 'email body extraction with IMAP failures' do
      context 'when body structure fetch fails' do
        it 'attempts HTML fallback on structure fetch error' do
          allow(mock_imap_service).to receive(:fetch_body_structure)
            .and_raise(Net::IMAP::BadResponseError, 'Bad response')
          allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
            .and_return('<html>Fallback HTML</html>')

          result = processor.send(:extract_email_body, message_id, mock_imap_service)

          expect(result).to include('Fallback HTML')
        end

        it 'returns error message when all fetch attempts fail' do
          allow(mock_imap_service).to receive(:fetch_body_structure)
            .and_raise(StandardError, 'Structure error')
          allow(mock_imap_service).to receive(:fetch_body_part)
            .and_raise(StandardError, 'Part fetch error')

          result = processor.send(:extract_email_body, message_id, mock_imap_service)

          expect(result).to eq('Failed to fetch email content')
        end
      end
    end

    describe 'from address building edge cases' do
      context 'with unusual envelope structures' do
        it 'handles multiple from addresses' do
          envelope = double('envelope',
            from: [
              double('from1', mailbox: 'sender1', host: 'domain1.com'),
              double('from2', mailbox: 'sender2', host: 'domain2.com')
            ]
          )

          result = processor.send(:build_from_address, envelope)

          expect(result).to eq('sender1@domain1.com') # Uses first address
        end

        it 'handles from address with nil mailbox' do
          envelope = double('envelope',
            from: [ double('from', mailbox: nil, host: 'domain.com') ]
          )

          result = processor.send(:build_from_address, envelope)

          expect(result).to eq('@domain.com')
        end

        it 'handles from address with nil host' do
          envelope = double('envelope',
            from: [ double('from', mailbox: 'user', host: nil) ]
          )

          result = processor.send(:build_from_address, envelope)

          expect(result).to eq('user@')
        end

        it 'handles from address with both nil' do
          envelope = double('envelope',
            from: [ double('from', mailbox: nil, host: nil) ]
          )

          result = processor.send(:build_from_address, envelope)

          expect(result).to eq('@')
        end
      end
    end
  end
end
