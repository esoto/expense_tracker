require 'rails_helper'

RSpec.describe Services::EmailProcessing::FetcherResponse, integration: true do
  describe '#initialize', integration: true do
    it 'sets default values when no parameters provided' do
      response = Services::EmailProcessing::FetcherResponse.new

      expect(response.success).to be false
      expect(response.errors).to eq([])
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
    end

    it 'sets provided values' do
      response = Services::EmailProcessing::FetcherResponse.new(
        success: true,
        errors: [ 'Error 1', 'Error 2' ],
        processed_emails_count: 5,
        total_emails_found: 10
      )

      expect(response.success).to be true
      expect(response.errors).to eq([ 'Error 1', 'Error 2' ])
      expect(response.processed_emails_count).to eq(5)
      expect(response.total_emails_found).to eq(10)
    end

    it 'converts single error to array' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: 'Single error')
      expect(response.errors).to eq([ 'Single error' ])
    end
  end

  describe '#success?', integration: true do
    it 'returns true when success is true' do
      response = Services::EmailProcessing::FetcherResponse.new(success: true)
      expect(response.success?).to be true
    end

    it 'returns false when success is false' do
      response = Services::EmailProcessing::FetcherResponse.new(success: false)
      expect(response.success?).to be false
    end
  end

  describe '#failure?', integration: true do
    it 'returns false when success is true' do
      response = Services::EmailProcessing::FetcherResponse.new(success: true)
      expect(response.failure?).to be false
    end

    it 'returns true when success is false' do
      response = Services::EmailProcessing::FetcherResponse.new(success: false)
      expect(response.failure?).to be true
    end
  end

  describe '#has_errors?', integration: true do
    it 'returns false when no errors' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: [])
      expect(response.has_errors?).to be false
    end

    it 'returns true when errors present' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: [ 'Error' ])
      expect(response.has_errors?).to be true
    end
  end

  describe '#error_messages', integration: true do
    it 'returns empty string when no errors' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: [])
      expect(response.error_messages).to eq('')
    end

    it 'returns single error message' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: [ 'Error message' ])
      expect(response.error_messages).to eq('Error message')
    end

    it 'joins multiple error messages with comma' do
      response = Services::EmailProcessing::FetcherResponse.new(errors: [ 'Error 1', 'Error 2' ])
      expect(response.error_messages).to eq('Error 1, Error 2')
    end
  end

  describe '#to_h', integration: true do
    it 'returns hash representation of response' do
      response = Services::EmailProcessing::FetcherResponse.new(
        success: true,
        errors: [ 'Warning' ],
        processed_emails_count: 3,
        total_emails_found: 5
      )

      expected_hash = {
        success: true,
        errors: [ 'Warning' ],
        processed_emails_count: 3,
        total_emails_found: 5
      }

      expect(response.to_h).to eq(expected_hash)
    end
  end

  describe '.success', integration: true do
    it 'creates successful response with default values' do
      response = Services::EmailProcessing::FetcherResponse.success

      expect(response.success?).to be true
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
      expect(response.errors).to eq([])
    end

    it 'creates successful response with provided values' do
      response = Services::EmailProcessing::FetcherResponse.success(
        processed_emails_count: 7,
        total_emails_found: 12,
        errors: [ 'Warning message' ]
      )

      expect(response.success?).to be true
      expect(response.processed_emails_count).to eq(7)
      expect(response.total_emails_found).to eq(12)
      expect(response.errors).to eq([ 'Warning message' ])
    end

    it 'can have success response with errors (warnings)' do
      response = Services::EmailProcessing::FetcherResponse.success(errors: [ 'Minor warning' ])

      expect(response.success?).to be true
      expect(response.has_errors?).to be true
      expect(response.errors).to eq([ 'Minor warning' ])
    end
  end

  describe '.failure', integration: true do
    it 'creates failure response with errors' do
      response = Services::EmailProcessing::FetcherResponse.failure(errors: [ 'Connection failed' ])

      expect(response.failure?).to be true
      expect(response.errors).to eq([ 'Connection failed' ])
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
    end

    it 'creates failure response with partial processing counts' do
      response = Services::EmailProcessing::FetcherResponse.failure(
        errors: [ 'Processing stopped' ],
        processed_emails_count: 2,
        total_emails_found: 8
      )

      expect(response.failure?).to be true
      expect(response.processed_emails_count).to eq(2)
      expect(response.total_emails_found).to eq(8)
      expect(response.errors).to eq([ 'Processing stopped' ])
    end
  end
end
