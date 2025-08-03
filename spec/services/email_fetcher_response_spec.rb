require 'rails_helper'

RSpec.describe EmailFetcherResponse do
  describe '#initialize' do
    it 'sets default values when no parameters provided' do
      response = EmailFetcherResponse.new
      
      expect(response.success).to be false
      expect(response.errors).to eq([])
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
    end

    it 'sets provided values' do
      response = EmailFetcherResponse.new(
        success: true,
        errors: ['Error 1', 'Error 2'],
        processed_emails_count: 5,
        total_emails_found: 10
      )
      
      expect(response.success).to be true
      expect(response.errors).to eq(['Error 1', 'Error 2'])
      expect(response.processed_emails_count).to eq(5)
      expect(response.total_emails_found).to eq(10)
    end

    it 'converts single error to array' do
      response = EmailFetcherResponse.new(errors: 'Single error')
      expect(response.errors).to eq(['Single error'])
    end
  end

  describe '#success?' do
    it 'returns true when success is true' do
      response = EmailFetcherResponse.new(success: true)
      expect(response.success?).to be true
    end

    it 'returns false when success is false' do
      response = EmailFetcherResponse.new(success: false)
      expect(response.success?).to be false
    end
  end

  describe '#failure?' do
    it 'returns false when success is true' do
      response = EmailFetcherResponse.new(success: true)
      expect(response.failure?).to be false
    end

    it 'returns true when success is false' do
      response = EmailFetcherResponse.new(success: false)
      expect(response.failure?).to be true
    end
  end

  describe '#has_errors?' do
    it 'returns false when no errors' do
      response = EmailFetcherResponse.new(errors: [])
      expect(response.has_errors?).to be false
    end

    it 'returns true when errors present' do
      response = EmailFetcherResponse.new(errors: ['Error'])
      expect(response.has_errors?).to be true
    end
  end

  describe '#error_messages' do
    it 'returns empty string when no errors' do
      response = EmailFetcherResponse.new(errors: [])
      expect(response.error_messages).to eq('')
    end

    it 'returns single error message' do
      response = EmailFetcherResponse.new(errors: ['Error message'])
      expect(response.error_messages).to eq('Error message')
    end

    it 'joins multiple error messages with comma' do
      response = EmailFetcherResponse.new(errors: ['Error 1', 'Error 2'])
      expect(response.error_messages).to eq('Error 1, Error 2')
    end
  end

  describe '#to_h' do
    it 'returns hash representation of response' do
      response = EmailFetcherResponse.new(
        success: true,
        errors: ['Warning'],
        processed_emails_count: 3,
        total_emails_found: 5
      )
      
      expected_hash = {
        success: true,
        errors: ['Warning'],
        processed_emails_count: 3,
        total_emails_found: 5
      }
      
      expect(response.to_h).to eq(expected_hash)
    end
  end

  describe '.success' do
    it 'creates successful response with default values' do
      response = EmailFetcherResponse.success
      
      expect(response.success?).to be true
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
      expect(response.errors).to eq([])
    end

    it 'creates successful response with provided values' do
      response = EmailFetcherResponse.success(
        processed_emails_count: 7,
        total_emails_found: 12,
        errors: ['Warning message']
      )
      
      expect(response.success?).to be true
      expect(response.processed_emails_count).to eq(7)
      expect(response.total_emails_found).to eq(12)
      expect(response.errors).to eq(['Warning message'])
    end

    it 'can have success response with errors (warnings)' do
      response = EmailFetcherResponse.success(errors: ['Minor warning'])
      
      expect(response.success?).to be true
      expect(response.has_errors?).to be true
      expect(response.errors).to eq(['Minor warning'])
    end
  end

  describe '.failure' do
    it 'creates failure response with errors' do
      response = EmailFetcherResponse.failure(errors: ['Connection failed'])
      
      expect(response.failure?).to be true
      expect(response.errors).to eq(['Connection failed'])
      expect(response.processed_emails_count).to eq(0)
      expect(response.total_emails_found).to eq(0)
    end

    it 'creates failure response with partial processing counts' do
      response = EmailFetcherResponse.failure(
        errors: ['Processing stopped'],
        processed_emails_count: 2,
        total_emails_found: 8
      )
      
      expect(response.failure?).to be true
      expect(response.processed_emails_count).to eq(2)
      expect(response.total_emails_found).to eq(8)
      expect(response.errors).to eq(['Processing stopped'])
    end
  end
end