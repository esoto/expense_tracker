require 'rails_helper'

RSpec.describe 'IMAP connection reuse', type: :service, unit: true do
  let(:email_account) { create(:email_account, :bac) }
  let(:service) { Services::ImapConnectionService.new(email_account) }
  let(:mock_imap) { instance_double(Net::IMAP) }
  let(:mock_envelope) do
    double('envelope',
      subject: 'Notificacion de transaccion',
      from: [double(mailbox: 'alerts', host: 'bac.net')],
      date: Time.current
    )
  end

  before do
    allow(Net::IMAP).to receive(:new).and_return(mock_imap)
    allow(mock_imap).to receive(:login)
    allow(mock_imap).to receive(:select)
    allow(mock_imap).to receive(:logout)
    allow(mock_imap).to receive(:disconnect)
    allow(mock_imap).to receive(:respond_to?).and_return(true)
    allow(mock_imap).to receive(:search).and_return([1, 2, 3])
    allow(mock_imap).to receive(:fetch).and_return([double(attr: {
      "ENVELOPE" => mock_envelope,
      "BODYSTRUCTURE" => double(media_type: "TEXT", subtype: "PLAIN", multipart?: false),
      "BODY[TEXT]" => "Monto: 5000 Comercio: Test"
    })])
  end

  it 'opens exactly 1 IMAP connection for multiple emails' do
    processor = instance_double(Services::EmailProcessing::Processor)
    allow(processor).to receive(:process_emails).and_return(processed_count: 3, total_count: 3, detected_expenses_count: 0)

    fetcher = Services::EmailProcessing::Fetcher.new(
      email_account,
      imap_service: service,
      email_processor: processor
    )

    fetcher.fetch_new_emails(since: 1.week.ago)

    expect(Net::IMAP).to have_received(:new).once
  end

  it 'authenticates and selects INBOX exactly once' do
    processor = instance_double(Services::EmailProcessing::Processor)
    allow(processor).to receive(:process_emails).and_return(processed_count: 3, total_count: 3, detected_expenses_count: 0)

    fetcher = Services::EmailProcessing::Fetcher.new(
      email_account,
      imap_service: service,
      email_processor: processor
    )

    fetcher.fetch_new_emails(since: 1.week.ago)

    expect(mock_imap).to have_received(:login).once
    expect(mock_imap).to have_received(:select).with("INBOX").once
  end

  it 'cleans up connection after processing completes' do
    processor = instance_double(Services::EmailProcessing::Processor)
    allow(processor).to receive(:process_emails).and_return(processed_count: 3, total_count: 3, detected_expenses_count: 0)

    fetcher = Services::EmailProcessing::Fetcher.new(
      email_account,
      imap_service: service,
      email_processor: processor
    )

    fetcher.fetch_new_emails(since: 1.week.ago)

    expect(mock_imap).to have_received(:logout).once
    expect(mock_imap).to have_received(:disconnect).once
  end
end
