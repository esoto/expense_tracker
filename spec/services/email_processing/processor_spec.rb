require 'rails_helper'

RSpec.describe Services::EmailProcessing::Processor, type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:metrics_collector) { instance_double(Services::SyncMetricsCollector) }
  let(:processor) { described_class.new(email_account, metrics_collector: metrics_collector) }
  let(:processor_without_metrics) { described_class.new(email_account) }
  let(:mock_imap_service) { instance_double(Services::ImapConnectionService) }

  describe '#initialize' do
    it 'sets email account and initializes empty errors' do
      expect(processor.email_account).to eq(email_account)
      expect(processor.errors).to be_empty
    end

    it 'accepts optional metrics collector' do
      expect(processor.metrics_collector).to eq(metrics_collector)
    end

    it 'works without metrics collector' do
      expect(processor_without_metrics.metrics_collector).to be_nil
    end

    it 'accepts optional sync_session' do
      sync_session = instance_double(SyncSession)
      p = described_class.new(email_account, sync_session: sync_session)
      expect(p.instance_variable_get(:@sync_session)).to eq(sync_session)
    end

    it 'defaults sync_session to nil' do
      expect(processor.instance_variable_get(:@sync_session)).to be_nil
    end
  end

  describe '#process_emails', integration: true do
    before do
      allow(metrics_collector).to receive(:track_operation).and_yield
    end

    context 'with empty message list' do
      it 'returns zero counts' do
        result = processor.process_emails([], mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(0)
        expect(result[:detected_expenses_count]).to eq(0)
      end
    end

    context 'with transaction emails' do
      let(:message_ids) { [ 1, 2, 3 ] }
      let(:transaction_envelope) { double('envelope', subject: 'BAC - Notificación de transacción', from: nil, message_id: '<txn@example.com>') }
      let(:non_transaction_envelope) { double('envelope', subject: 'Regular email', from: nil, message_id: '<regular@example.com>') }

      before do
        allow(mock_imap_service).to receive(:fetch_envelope).with(1).and_return(transaction_envelope)
        allow(mock_imap_service).to receive(:fetch_envelope).with(2).and_return(non_transaction_envelope)
        allow(mock_imap_service).to receive(:fetch_envelope).with(3).and_return(transaction_envelope)

        allow(processor).to receive(:extract_email_data).and_return({
          message_id: 1,
          from: 'bank@bac.co.cr',
          subject: 'Transaction',
          date: Time.current,
          body: 'Transaction details'
        })

        allow(ProcessEmailJob).to receive(:perform_later)
      end

      it 'processes only transaction emails' do
        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(2)
        expect(result[:total_count]).to eq(3)
        expect(result[:detected_expenses_count]).to eq(2)
      end

      it 'queues ProcessEmailJob for transaction emails' do
        processor.process_emails(message_ids, mock_imap_service)

        expect(ProcessEmailJob).to have_received(:perform_later).twice
      end

      it 'calls progress callback when provided' do
        progress_calls = []

        processor.process_emails(message_ids, mock_imap_service) do |processed, detected, expense_data|
          progress_calls << [ processed, detected, expense_data ]
        end

        expect(progress_calls.length).to eq(3)
        expect(progress_calls[0][0..1]).to eq([ 1, 1 ])  # First email (transaction)
        expect(progress_calls[1][0..1]).to eq([ 2, 1 ])  # Second email (non-transaction)
        expect(progress_calls[2][0..1]).to eq([ 3, 2 ])  # Third email (transaction)
      end

      it 'works without progress callback' do
        expect {
          processor.process_emails(message_ids, mock_imap_service)
        }.not_to raise_error
      end
    end

    context 'with missing envelope' do
      let(:message_ids) { [ 1 ] }

      before do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(nil)
      end

      it 'skips emails with missing envelopes' do
        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(1)
        expect(result[:detected_expenses_count]).to eq(0)
      end
    end

    context 'with failed email data extraction' do
      let(:message_ids) { [ 1 ] }
      let(:transaction_envelope) { double('envelope', subject: 'BAC - Notificación de transacción', message_id: '<failed-extraction@example.com>') }

      before do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(transaction_envelope)
        allow(processor).to receive(:extract_email_data).and_return(nil)
        allow(ProcessEmailJob).to receive(:perform_later)
      end

      it 'skips emails when data extraction fails' do
        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(1)
        expect(result[:detected_expenses_count]).to eq(0)
        expect(ProcessEmailJob).not_to have_received(:perform_later)
      end
    end

    context 'with processing errors' do
      let(:message_ids) { [ 1 ] }

      before do
        allow(mock_imap_service).to receive(:fetch_envelope)
          .and_raise(StandardError, 'IMAP error')
      end

      it 'handles errors gracefully and continues processing' do
        result = processor.process_emails(message_ids, mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(1)
        expect(result[:detected_expenses_count]).to eq(0)
        expect(processor.errors).to include('Error processing email: IMAP error')
      end
    end
  end

  describe '#process_emails progress callback', unit: true do
    let(:imap_service) { instance_double(Services::ImapConnectionService) }

    it 'passes 3 arguments to progress callback' do
      envelope = double("envelope", subject: "Notificación de transacción", from: nil, date: Time.current, message_id: "<progress-1@example.com>")
      allow(imap_service).to receive(:fetch_envelope).and_return(envelope)
      allow(imap_service).to receive(:fetch_body_structure).and_return(nil)
      allow(imap_service).to receive(:fetch_text_body).and_return("Test body")
      allow(ProcessEmailJob).to receive(:perform_later)

      callback_args = []
      processor_without_metrics.process_emails([ 1 ], imap_service) do |*args|
        callback_args = args
      end

      expect(callback_args.length).to eq(3)
    end

    it 'passes nil as third arg for non-expense emails' do
      non_transaction_envelope = double("envelope", subject: "Newsletter", from: nil, date: Time.current, message_id: "<progress-2@example.com>")
      allow(imap_service).to receive(:fetch_envelope).and_return(non_transaction_envelope)

      callback_args = []
      processor_without_metrics.process_emails([ 1 ], imap_service) do |*args|
        callback_args = args
      end

      expect(callback_args.length).to eq(3)
      expect(callback_args[2]).to be_nil
    end
  end

  describe '#transaction_email?', integration: true do
    it 'identifies transaction emails with "transacción"' do
      result = processor.send(:transaction_email?, 'Información de transacción realizada')
      expect(result).to be true
    end

    it 'identifies transaction emails with "Notificaci"' do
      result = processor.send(:transaction_email?, 'BAC - Notificación de compra')
      expect(result).to be true
    end

    it 'rejects non-transaction emails' do
      result = processor.send(:transaction_email?, 'Promotional email')
      expect(result).to be false
    end

    it 'handles nil subjects' do
      result = processor.send(:transaction_email?, nil)
      expect(result).to be false
    end
  end

  describe '#decode_subject', unit: true do
    it 'decodes RFC 2047 quoted-printable encoded subjects' do
      encoded = "=?UTF-8?Q?Notificaci=C3=B3n_de_transacci=C3=B3n_AUTO_MERCADO?="
      result = processor.send(:decode_subject, encoded)
      expect(result).to eq("Notificación de transacción AUTO MERCADO")
    end

    it 'decodes multi-part RFC 2047 subjects' do
      encoded = "=?UTF-8?Q?Notificaci=C3=B3n_de_transacci=C3=B3n_AUTO_M?= =?UTF-8?Q?ERCADO_CARTAGO?="
      result = processor.send(:decode_subject, encoded)
      expect(result).to include("Notificación de transacción")
      expect(result).to include("AUTO MERCADO")
    end

    it 'returns plain subjects unchanged' do
      result = processor.send(:decode_subject, "Plain subject")
      expect(result).to eq("Plain subject")
    end

    it 'handles empty string' do
      result = processor.send(:decode_subject, "")
      expect(result).to eq("")
    end

    it 'decodes RFC 2047 Base64 encoded subjects' do
      # "Notificación de transacción" in Base64
      encoded = "=?UTF-8?B?Tm90aWZpY2FjacOzbiBkZSB0cmFuc2FjY2nDs24=?="
      result = processor.send(:decode_subject, encoded)
      expect(result).to eq("Notificación de transacción")
    end
  end

  describe '#transaction_email? with decoded subjects', unit: true do
    it 'matches decoded QP subject containing transacción' do
      decoded = "Notificación de transacción AUTO MERCADO CARTAGO F 07-04-2026 - 12:09"
      result = processor.send(:transaction_email?, decoded)
      expect(result).to be true
    end

    it 'matches decoded B64 subject containing transacción' do
      # Simulate what decode_subject returns from a Base64 encoded subject
      encoded = "=?UTF-8?B?Tm90aWZpY2FjacOzbiBkZSB0cmFuc2FjY2nDs24gQVVUTyBNRVJDQURP?="
      decoded = processor.send(:decode_subject, encoded)
      result = processor.send(:transaction_email?, decoded)
      expect(result).to be true
    end
  end

  describe '#extract_email_data', integration: true do
    let(:message_id) { 123 }
    let(:envelope) do
      double('envelope',
        subject: 'Test Transaction',
        date: Time.current,
        from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ],
        message_id: '<extract-data@example.com>'
      )
    end
    let(:email_body) { 'Transaction details here' }

    before do
      allow(processor).to receive(:extract_email_body).and_return(email_body)
    end

    it 'extracts complete email data structure' do
      result = processor.send(:extract_email_data, message_id, envelope, mock_imap_service)

      expect(result).to include(
        message_id: message_id,
        rfc_message_id: '<extract-data@example.com>',
        from: 'bank@bac.co.cr',
        subject: 'Test Transaction',
        date: envelope.date,
        body: email_body
      )
    end

    it 'returns nil if body extraction fails' do
      allow(processor).to receive(:extract_email_body).and_return(nil)

      result = processor.send(:extract_email_data, message_id, envelope, mock_imap_service)
      expect(result).to be_nil
    end
  end

  describe '#extract_email_body', integration: true do
    let(:message_id) { 123 }
    let(:simple_structure) { double('structure', multipart?: false) }
    let(:multipart_structure) { double('structure', multipart?: true) }

    context 'with simple email structure' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure).and_return(simple_structure)
        allow(mock_imap_service).to receive(:fetch_text_body).and_return('Simple text body')
      end

      it 'fetches text body for simple structure' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Simple text body')
      end
    end

    context 'with nil body structure' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure).and_return(nil)
        allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback text')
      end

      it 'falls back to text body when structure is nil' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Fallback text')
      end
    end

    context 'with multipart email structure' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure).and_return(multipart_structure)
        allow(processor).to receive(:extract_multipart_body).and_return('Multipart content')
      end

      it 'delegates to multipart extraction' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Multipart content')
      end
    end

    context 'with extraction errors and successful HTML fallback' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure)
          .and_raise(StandardError, 'Structure error')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
          .and_return('<html><body>HTML content</body></html>')
        allow(processor).to receive(:extract_text_from_html).and_return('HTML content')
      end

      it 'falls back to HTML extraction' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('HTML content')
      end
    end

    context 'with extraction errors and nil HTML content' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure)
          .and_raise(StandardError, 'Structure error')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
          .and_return(nil)
      end

      it 'returns failure message when HTML content is nil' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Failed to fetch email content')
      end
    end

    context 'with extraction errors and HTML fetch failure' do
      before do
        allow(mock_imap_service).to receive(:fetch_body_structure)
          .and_raise(StandardError, 'Structure error')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
          .and_raise(StandardError, 'HTML fetch error')
      end

      it 'returns failure message when HTML fetch fails' do
        result = processor.send(:extract_email_body, message_id, mock_imap_service)
        expect(result).to eq('Failed to fetch email content')
      end
    end
  end

  describe '#extract_multipart_body', integration: true do
    let(:message_id) { 123 }
    let(:multipart_structure) { double('structure') }

    context 'with text part available' do
      before do
        allow(processor).to receive(:find_text_part).and_return('1')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '1')
          .and_return('Plain text content')
      end

      it 'returns text part content' do
        result = processor.send(:extract_multipart_body, message_id, multipart_structure, mock_imap_service)
        expect(result).to eq('Plain text content')
      end
    end

    context 'with only HTML part available' do
      before do
        allow(processor).to receive(:find_text_part).and_return(nil)
        allow(processor).to receive(:find_html_part).and_return('2')
        allow(mock_imap_service).to receive(:fetch_body_part).with(message_id, '2')
          .and_return('<html>HTML content</html>')
        allow(processor).to receive(:extract_text_from_html).and_return('HTML content')
      end

      it 'extracts and converts HTML content' do
        result = processor.send(:extract_multipart_body, message_id, multipart_structure, mock_imap_service)
        expect(result).to eq('HTML content')
      end
    end

    context 'with no text or HTML parts' do
      before do
        allow(processor).to receive(:find_text_part).and_return(nil)
        allow(processor).to receive(:find_html_part).and_return(nil)
        allow(mock_imap_service).to receive(:fetch_text_body).and_return('Fallback content')
      end

      it 'falls back to basic text fetch' do
        result = processor.send(:extract_multipart_body, message_id, multipart_structure, mock_imap_service)
        expect(result).to eq('Fallback content')
      end
    end
  end

  describe '#find_text_part', integration: true do
    let(:text_part) { double('part', media_type: 'TEXT', subtype: 'PLAIN') }
    let(:html_part) { double('part', media_type: 'TEXT', subtype: 'HTML') }

    context 'with simple text structure' do
      let(:body_structure) { double('structure', media_type: 'TEXT', subtype: 'PLAIN', multipart?: false) }

      it 'returns "1" for simple text' do
        result = processor.send(:find_text_part, body_structure)
        expect(result).to eq('1')
      end
    end

    context 'with multipart structure containing text' do
      let(:body_structure) do
        double('structure',
          multipart?: true,
          media_type: nil,
          subtype: nil,
          parts: [ text_part, html_part ]
        )
      end

      it 'returns part number for text/plain' do
        result = processor.send(:find_text_part, body_structure)
        expect(result).to eq('1')
      end
    end

    context 'with no text parts' do
      let(:body_structure) do
        double('structure',
          multipart?: true,
          media_type: nil,
          subtype: nil,
          parts: [ html_part ]
        )
      end

      it 'returns nil when no text/plain found' do
        result = processor.send(:find_text_part, body_structure)
        expect(result).to be_nil
      end
    end
  end

  describe '#find_html_part', integration: true do
    let(:text_part) { double('part', media_type: 'TEXT', subtype: 'PLAIN') }
    let(:html_part) { double('part', media_type: 'TEXT', subtype: 'HTML') }

    context 'with simple HTML structure' do
      let(:body_structure) { double('structure', media_type: 'TEXT', subtype: 'HTML', multipart?: false) }

      it 'returns "1" for simple HTML' do
        result = processor.send(:find_html_part, body_structure)
        expect(result).to eq('1')
      end
    end

    context 'with multipart structure containing HTML' do
      let(:body_structure) do
        double('structure',
          multipart?: true,
          media_type: nil,
          subtype: nil,
          parts: [ text_part, html_part ]
        )
      end

      it 'returns part number for text/html' do
        result = processor.send(:find_html_part, body_structure)
        expect(result).to eq('2')
      end
    end
  end

  describe '#extract_text_from_html', unit: true do
    it 'removes HTML tags and normalizes text' do
      html = '<html><body><h1>Title</h1><p>Content here</p></body></html>'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Title Content here')
    end

    it 'decodes named HTML entities including Spanish accented characters' do
      html = 'M&aacute;s informaci&oacute;n &amp; detalles'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Más información & detalles')
    end

    it 'decodes uppercase Spanish named entities' do
      html = '&Aacute;ngel &Eacute;xito &Iacute;ndice &Oacute;scar &Uacute;til &Ntilde;o&ntilde;o'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Ángel Éxito Índice Óscar Útil Ñoño')
    end

    it 'decodes numeric decimal and hexadecimal HTML entities' do
      html = '&#193; &#x00E9;'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Á é')
    end

    it 'removes style and script tags completely' do
      html = '<html><head><style>body{color:red}</style></head><body><script>alert("test")</script><p>Content</p></body></html>'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Content')
    end

    it 'handles quoted-printable encoding' do
      html = "Line one=\r\nLine two with =41 encoded character"
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Line oneLine two with A encoded character')
    end

    it 'handles ASCII-8BIT encoding' do
      html = '<html>Content</html>'
      html.force_encoding('ASCII-8BIT')

      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Content')
    end

    it 'handles malformed/partial HTML without raising' do
      html = '<p>Unclosed tag <b>bold text <p>Second paragraph'
      expect { processor.send(:extract_text_from_html, html) }.not_to raise_error
    end

    it 'returns extracted text from malformed HTML' do
      html = '<p>Unclosed tag <b>bold text'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to include('Unclosed tag')
      expect(result).to include('bold text')
    end

    it 'returns empty string for nil input' do
      result = processor.send(:extract_text_from_html, nil)
      expect(result).to eq('')
    end

    it 'returns empty string for empty string input' do
      result = processor.send(:extract_text_from_html, '')
      expect(result).to eq('')
    end

    it 'normalizes multiple whitespace characters to single space' do
      html = '<p>Word1   Word2</p><p>  Word3  </p>'
      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq('Word1 Word2 Word3')
    end

    it 'covers the encoding error rescue block for CompatibilityError' do
      html = "<html><body>Test content</body></html>"

      expect(Rails.logger).to receive(:warn).with(/HTML encoding error:/)

      allow(processor).to receive(:extract_text_from_html) do |content|
        begin
          raise Encoding::CompatibilityError.new("test encoding error")
        rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError => e
          Rails.logger.warn "HTML encoding error: #{e.message}"
          simple_text = content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
          simple_text.force_encoding("UTF-8")
        end
      end

      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq("Test content")
      expect(result.encoding.name).to eq('UTF-8')
    end

    it 'covers the encoding error rescue block for UndefinedConversionError' do
      html = "<html><body>Test content</body></html>"

      expect(Rails.logger).to receive(:warn).with(/HTML encoding error:/)

      allow(processor).to receive(:extract_text_from_html) do |content|
        begin
          raise Encoding::UndefinedConversionError.new("test conversion error")
        rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError => e
          Rails.logger.warn "HTML encoding error: #{e.message}"
          simple_text = content.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
          simple_text.force_encoding("UTF-8")
        end
      end

      result = processor.send(:extract_text_from_html, html)
      expect(result).to eq("Test content")
      expect(result.encoding.name).to eq('UTF-8')
    end
  end

  describe '#build_from_address', integration: true do
    context 'with valid from address' do
      let(:envelope) do
        double('envelope',
          from: [ double('from', mailbox: 'notifications', host: 'bank.com') ]
        )
      end

      it 'builds email address from envelope' do
        result = processor.send(:build_from_address, envelope)
        expect(result).to eq('notifications@bank.com')
      end
    end

    context 'with missing from address' do
      let(:envelope) { double('envelope', from: nil) }

      it 'returns default unknown address' do
        result = processor.send(:build_from_address, envelope)
        expect(result).to eq('unknown@unknown.com')
      end
    end

    context 'with empty from array' do
      let(:envelope) { double('envelope', from: []) }

      it 'returns default unknown address' do
        result = processor.send(:build_from_address, envelope)
        expect(result).to eq('unknown@unknown.com')
      end
    end
  end

  describe 'error handling', integration: true do
    describe '#add_error', integration: true do
      it 'adds error to errors array and logs to Rails logger' do
        expect(Rails.logger).to receive(:error).with("[Services::EmailProcessing::Processor] #{email_account.email}: Test error")

        processor.send(:add_error, "Test error")

        expect(processor.errors).to include("Test error")
      end
    end
  end

  describe 'metrics integration', integration: true do
    let(:message_id) { 123 }
    let(:envelope) { double('envelope', subject: 'BAC - Notificación de transacción', date: Time.current, from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ], message_id: '<metrics@example.com>') }

    describe '#process_single_email with metrics' do
      it 'tracks operation with metrics collector when available' do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
        allow(processor).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)

        expect(metrics_collector).to receive(:track_operation).with(
          :parse_email,
          email_account,
          { message_id: message_id }
        ).and_yield

        processor.send(:process_single_email, message_id, mock_imap_service)
      end

      it 'processes without metrics when collector not available' do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(envelope)
        allow(processor_without_metrics).to receive(:extract_email_data).and_return({ body: 'test' })
        allow(ProcessEmailJob).to receive(:perform_later)

        expect {
          processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)
        }.not_to raise_error
      end
    end
  end

  describe '#detect_and_handle_conflict', integration: true do
    let(:email_data) { { body: 'Transaction details', date: Time.current } }
    let(:parsing_rule) { instance_double(ParsingRule) }
    let(:parsing_strategy) { instance_double(Services::EmailProcessing::Strategies::Regex) }
    let(:sync_session) { instance_double(SyncSession) }
    let(:conflict_detector) { instance_double(Services::ConflictDetectionService) }
    let(:expense_data) { { amount: 100, description: 'Purchase' } }

    before do
      allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(parsing_rule)
      allow(Services::EmailProcessing::StrategyFactory).to receive(:create_strategy).and_return(parsing_strategy)
      allow(parsing_strategy).to receive(:parse_email).and_return(expense_data)
      allow(metrics_collector).to receive(:track_operation).and_yield
    end

    context 'with active sync session threaded via constructor' do
      let(:processor_with_session) { described_class.new(email_account, metrics_collector: metrics_collector, sync_session: sync_session) }

      before do
        allow(Services::ConflictDetectionService).to receive(:new).with(sync_session, metrics_collector: metrics_collector).and_return(conflict_detector)
      end

      it 'returns nil when conflict is detected' do
        allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(true)

        result = processor_with_session.send(:detect_and_handle_conflict, email_data)
        expect(result).to be_nil
      end

      it 'returns expense data hash when no conflict' do
        allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)

        result = processor_with_session.send(:detect_and_handle_conflict, email_data)
        expect(result).to be_a(Hash)
        expect(result[:amount]).to eq(100)
        expect(result[:email_account_id]).to eq(email_account.id)
        expect(result[:raw_email_content]).to eq(email_data[:body])
      end

      it 'does not call SyncSession.active.last' do
        allow(conflict_detector).to receive(:detect_conflict_for_expense).and_return(false)
        expect(SyncSession).not_to receive(:active)

        processor_with_session.send(:detect_and_handle_conflict, email_data)
      end
    end

    context 'without sync session (nil)' do
      it 'returns expense data hash when no sync session' do
        result = processor.send(:detect_and_handle_conflict, email_data)
        expect(result).to be_a(Hash)
        expect(result[:amount]).to eq(100)
      end
    end

    context 'when no parsing rule exists' do
      before do
        allow(ParsingRule).to receive_message_chain(:active, :for_bank, :first).and_return(nil)
      end

      it 'returns false when no parsing rule found' do
        result = processor.send(:detect_and_handle_conflict, email_data)
        expect(result).to be false
      end
    end

    context 'when parser returns nil' do
      before do
        allow(parsing_strategy).to receive(:parse_email).and_return(nil)
      end

      it 'returns false when expense data cannot be parsed' do
        result = processor.send(:detect_and_handle_conflict, email_data)
        expect(result).to be false
      end
    end

    context 'with error during conflict detection' do
      let(:processor_with_session) { described_class.new(email_account, metrics_collector: metrics_collector, sync_session: sync_session) }

      before do
        allow(Services::ConflictDetectionService).to receive(:new).and_raise(StandardError, 'Detection error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns false' do
        expect(Rails.logger).to receive(:error).with('[Services::EmailProcessing::Processor] Error detecting conflict: Detection error')

        result = processor_with_session.send(:detect_and_handle_conflict, email_data)
        expect(result).to be false
      end
    end
  end

  describe 'idempotent skip gate keyed on RFC822 Message-ID', integration: true do
    let(:message_id) { 42 } # IMAP sequence number — fetch mechanics only, never the idempotency key
    let(:rfc_message_id) { '<abc-123@mail.bank.example>' }
    let(:envelope) do
      double('envelope',
        subject: 'BAC - Notificación de transacción',
        from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ],
        date: Time.current,
        message_id: rfc_message_id)
    end

    before do
      allow(mock_imap_service).to receive(:fetch_envelope).with(message_id).and_return(envelope)
    end

    context 'when the RFC822 Message-ID was already processed' do
      before do
        create(:processed_email, message_id: rfc_message_id, email_account: email_account)
      end

      it 'skips with the standard result before any parsing or conflict work' do
        expect(Services::ConflictDetectionService).not_to receive(:new)
        expect(ProcessEmailJob).not_to receive(:perform_later)
        expect(mock_imap_service).not_to receive(:fetch_body_structure)
        expect(mock_imap_service).not_to receive(:fetch_text_body)

        result = processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)

        expect(result).to eq(processed: false, expense_created: false)
      end

      it 'is counted as skipped (not processed) at the process_emails level' do
        result = processor_without_metrics.process_emails([ message_id ], mock_imap_service)

        expect(result[:processed_count]).to eq(0)
        expect(result[:total_count]).to eq(1)
        expect(result[:detected_expenses_count]).to eq(0)
      end

      it 'does not create a new ProcessedEmail record' do
        expect {
          processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)
        }.not_to change(ProcessedEmail, :count)
      end

      it 'matches bracket/case variants through the shared normalization' do
        variant_envelope = double('envelope',
          subject: 'BAC - Notificación de transacción',
          from: nil, date: Time.current,
          message_id: '  <ABC-123@MAIL.BANK.EXAMPLE>  ')
        allow(mock_imap_service).to receive(:fetch_envelope).with(message_id).and_return(variant_envelope)

        result = processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)

        expect(result).to eq(processed: false, expense_created: false)
      end
    end

    # REGRESSION (architect): IMAP sequence numbers are unstable across
    # sessions (RFC 3501 — expunges shift them). A reused sequence position
    # carrying a DIFFERENT email must be processed, never skipped.
    context 'when the same sequence number carries a different Message-ID' do
      before do
        create(:processed_email, message_id: '<some-other-email@mail.bank.example>', email_account: email_account)
        allow(processor_without_metrics).to receive(:extract_email_data).and_return(nil)
      end

      it 'does not skip — proceeds into the transaction pipeline' do
        processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)

        expect(processor_without_metrics).to have_received(:extract_email_data)
      end
    end

    context 'when the Message-ID header is nil (malformed email)' do
      let(:envelope) do
        double('envelope',
          subject: 'BAC - Notificación de transacción',
          from: nil, date: Time.current,
          message_id: nil)
      end

      before do
        allow(processor_without_metrics).to receive(:extract_email_data).and_return(nil)
      end

      it 'never skips, even when a blank-keyed record could theoretically match' do
        processor_without_metrics.send(:process_single_email, message_id, mock_imap_service)

        expect(processor_without_metrics).to have_received(:extract_email_data)
      end
    end
  end

  describe '#process_email_with_metrics recording at terminal outcomes', integration: true do
    let(:message_id) { 55 } # IMAP sequence number
    let(:rfc_message_id) { '<Terminal-55@Mail.Bank.Example>' }

    context 'when the email is not a transaction email' do
      let(:non_transaction_envelope) do
        double('envelope', subject: 'Newsletter', from: [ double('from', mailbox: 'news', host: 'example.com') ], date: Time.current, message_id: rfc_message_id)
      end

      before do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(non_transaction_envelope)
      end

      it 'records a ProcessedEmail keyed on the normalized RFC822 Message-ID' do
        expect {
          processor_without_metrics.send(:process_email_with_metrics, message_id, mock_imap_service)
        }.to change(ProcessedEmail, :count).by(1)

        recorded = ProcessedEmail.last
        expect(recorded.message_id).to eq('terminal-55@mail.bank.example')
        expect(recorded.email_account).to eq(email_account)
        expect(recorded.user).to eq(email_account.user)
        expect(recorded.subject).to eq('Newsletter')
      end

      it 'does not raise when recording fails' do
        allow(ProcessedEmail).to receive(:find_or_create_by!).and_raise(StandardError, 'boom')
        allow(Rails.logger).to receive(:error)

        expect {
          processor_without_metrics.send(:process_email_with_metrics, message_id, mock_imap_service)
        }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(
          a_string_matching(/Failed to record processed email/)
        )
      end

      context 'with a nil Message-ID header' do
        let(:non_transaction_envelope) do
          double('envelope', subject: 'Newsletter', from: nil, date: Time.current, message_id: nil)
        end

        it 'records nothing and does not raise' do
          expect {
            processor_without_metrics.send(:process_email_with_metrics, message_id, mock_imap_service)
          }.not_to change(ProcessedEmail, :count)
        end
      end
    end

    context 'when a conflict is detected for a transaction email' do
      let(:sync_session_for_conflict) { instance_double(SyncSession, id: 1) }
      let(:processor_with_session) { described_class.new(email_account, sync_session: sync_session_for_conflict) }
      let(:transaction_envelope) do
        double('envelope', subject: 'Notificación de transacción', from: [ double('from', mailbox: 'bank', host: 'bac.co.cr') ], date: Time.current, message_id: rfc_message_id)
      end

      before do
        allow(mock_imap_service).to receive(:fetch_envelope).and_return(transaction_envelope)
        allow(processor_with_session).to receive(:extract_email_data).and_return({
          message_id: message_id,
          rfc_message_id: rfc_message_id,
          from: 'bank@bac.co.cr',
          subject: 'Notificación de transacción',
          date: Time.current,
          body: 'body'
        })
        allow(processor_with_session).to receive(:detect_and_handle_conflict).and_return(nil)
        allow(ProcessEmailJob).to receive(:perform_later)
      end

      it 'records a ProcessedEmail keyed on the normalized RFC822 Message-ID' do
        expect {
          processor_with_session.send(:process_email_with_metrics, message_id, mock_imap_service)
        }.to change(ProcessedEmail, :count).by(1)

        expect(ProcessedEmail.last.message_id).to eq('terminal-55@mail.bank.example')
      end

      it 'does not enqueue ProcessEmailJob' do
        processor_with_session.send(:process_email_with_metrics, message_id, mock_imap_service)

        expect(ProcessEmailJob).not_to have_received(:perform_later)
      end
    end
  end
end
