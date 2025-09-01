# frozen_string_literal: true

require 'rails_helper'
require 'support/broadcast_service_test_helper'

RSpec.describe Infrastructure::BroadcastService::RequestValidator, :unit do
  include BroadcastServiceTestHelper
  
  before(:each) do
    setup_broadcast_test_environment
  end
  
  after(:each) do
    teardown_broadcast_test_environment
  end
  
  let(:channel) { 'TestChannel' }
  let(:target) { create_test_target(id: 42) }
  let(:data) { create_test_data(size: :small) }
  
  describe '.validate!' do
    context 'valid requests' do
      it 'passes validation for valid parameters' do
        expect {
          described_class.validate!(channel, target, data)
        }.not_to raise_error
      end
      
      it 'accepts string channels' do
        expect {
          described_class.validate!('TestStringChannel', target, data)
        }.not_to raise_error
      end
      
      it 'accepts various data types' do
        # Hash data
        expect {
          described_class.validate!(channel, target, { key: 'value' })
        }.not_to raise_error
        
        # Array data
        expect {
          described_class.validate!(channel, target, [1, 2, 3])
        }.not_to raise_error
        
        # String data
        expect {
          described_class.validate!(channel, target, "string data")
        }.not_to raise_error
        
        # Numeric data
        expect {
          described_class.validate!(channel, target, 42)
        }.not_to raise_error
      end
      
      it 'accepts targets with id method' do
        target_with_id = double("Target", id: 999, class: double(name: "Model"))
        
        expect {
          described_class.validate!(channel, target_with_id, data)
        }.not_to raise_error
      end
    end
    
    context 'nil parameter validation' do
      it 'raises ArgumentError for nil channel' do
        expect {
          described_class.validate!(nil, target, data)
        }.to raise_error(ArgumentError, "Channel cannot be nil")
      end
      
      it 'raises ArgumentError for nil target' do
        expect {
          described_class.validate!(channel, nil, data)
        }.to raise_error(ArgumentError, "Target cannot be nil")
      end
      
      it 'raises ArgumentError for nil data' do
        expect {
          described_class.validate!(channel, target, nil)
        }.to raise_error(ArgumentError, "Data cannot be nil")
      end
    end
    
    context 'target validation' do
      it 'raises ArgumentError for target without id method' do
        invalid_target = double("InvalidTarget", class: double(name: "Model"))
        
        expect {
          described_class.validate!(channel, invalid_target, data)
        }.to raise_error(ArgumentError, "Target must have an id")
      end
      
      it 'accepts target with nil id value' do
        target_with_nil_id = double("Target", id: nil, class: double(name: "Model"))
        
        expect {
          described_class.validate!(channel, target_with_nil_id, data)
        }.not_to raise_error
      end
      
      it 'accepts target with string id' do
        target_with_string_id = double("Target", id: "abc123", class: double(name: "Model"))
        
        expect {
          described_class.validate!(channel, target_with_string_id, data)
        }.not_to raise_error
      end
    end
    
    context 'data size validation' do
      it 'accepts data within size limit' do
        medium_data = create_test_data(size: :medium)
        
        expect {
          described_class.validate!(channel, target, medium_data)
        }.not_to raise_error
      end
      
      it 'raises ArgumentError for oversized data' do
        oversized_data = create_test_data(size: :oversized)
        
        expect {
          described_class.validate!(channel, target, oversized_data)
        }.to raise_error(ArgumentError, /Data size .* exceeds maximum/)
      end
      
      it 'calculates size correctly for different data types' do
        # Just under 64KB limit
        large_but_valid = { data: "x" * 65_000 }
        
        expect {
          described_class.validate!(channel, target, large_but_valid)
        }.not_to raise_error
        
        # Just over 64KB limit
        too_large = { data: "x" * 66_000 }
        
        expect {
          described_class.validate!(channel, target, too_large)
        }.to raise_error(ArgumentError, /Data size .* exceeds maximum/)
      end
      
      it 'handles complex nested data structures' do
        nested_data = {
          level1: {
            level2: {
              level3: {
                array: Array.new(100) { |i| "item_#{i}" },
                hash: Hash[*(1..100).map { |i| ["key#{i}", "value#{i}"] }.flatten]
              }
            }
          }
        }
        
        expect {
          described_class.validate!(channel, target, nested_data)
        }.not_to raise_error
      end
    end
    
    context 'channel existence validation' do
      it 'validates channel can be constantize' do
        # Mock the private validation method to succeed
        allow(described_class).to receive(:validate_channel_exists!).with(channel)
        
        expect {
          described_class.validate!(channel, target, data)
        }.not_to raise_error
      end
      
      it 'raises ArgumentError for non-existent channel' do
        invalid_channel = 'NonExistentChannel'
        # Mock the private validation method to raise error
        allow(described_class).to receive(:validate_channel_exists!).with(invalid_channel)
          .and_raise(ArgumentError, "Channel NonExistentChannel does not exist")
        
        expect {
          described_class.validate!(invalid_channel, target, data)
        }.to raise_error(ArgumentError, "Channel NonExistentChannel does not exist")
      end
      
      it 'handles module-namespaced channels' do
        namespaced_channel = 'Module::Nested::TestChannel'
        # Mock the private validation method to succeed
        allow(described_class).to receive(:validate_channel_exists!).with(namespaced_channel)
        
        expect {
          described_class.validate!(namespaced_channel, target, data)
        }.not_to raise_error
      end
    end
    
    context 'edge cases' do
      it 'handles empty string channel' do
        expect {
          described_class.validate!('', target, data)
        }.to raise_error(ArgumentError)
      end
      
      it 'handles empty data structures' do
        # Empty hash
        expect {
          described_class.validate!(channel, target, {})
        }.not_to raise_error
        
        # Empty array
        expect {
          described_class.validate!(channel, target, [])
        }.not_to raise_error
        
        # Empty string
        expect {
          described_class.validate!(channel, target, '')
        }.not_to raise_error
      end
      
      it 'handles special characters in data' do
        special_data = {
          unicode: "🚀 Unicode émojis ñ",
          control: "\n\t\r",
          quotes: "\"double\" and 'single'",
          html: "<script>alert('xss')</script>"
        }
        
        expect {
          described_class.validate!(channel, target, special_data)
        }.not_to raise_error
      end
      
      it 'handles circular references in data' do
        circular_data = { key: 'value' }
        circular_data[:self] = circular_data
        
        # Should handle circular reference when converting to JSON
        expect {
          described_class.validate!(channel, target, circular_data)
        }.to raise_error(ArgumentError)
      end
      
      it 'handles frozen data objects' do
        frozen_data = { key: 'value' }.freeze
        
        expect {
          described_class.validate!(channel, target, frozen_data)
        }.not_to raise_error
      end
    end
    
    context 'performance considerations' do
      it 'validates quickly for small data' do
        start_time = Time.current
        
        100.times do
          described_class.validate!(channel, target, data)
        end
        
        elapsed = Time.current - start_time
        expect(elapsed).to be < 0.1 # Should complete 100 validations in under 100ms
      end
      
      it 'efficiently handles large but valid data' do
        large_data = { items: Array.new(1000) { |i| { id: i, name: "Item #{i}" } } }
        
        start_time = Time.current
        described_class.validate!(channel, target, large_data)
        elapsed = Time.current - start_time
        
        expect(elapsed).to be < 0.05 # Should validate in under 50ms
      end
    end
    
    context 'error message clarity' do
      it 'provides clear error message for nil channel' do
        expect {
          described_class.validate!(nil, target, data)
        }.to raise_error(ArgumentError, "Channel cannot be nil")
      end
      
      it 'provides size information in error message' do
        oversized_data = { data: "x" * 70_000 }
        
        expect {
          described_class.validate!(channel, target, oversized_data)
        }.to raise_error(ArgumentError, /Data size \(\d+ bytes\) exceeds maximum \(\d+ bytes\)/)
      end
      
      it 'includes channel name in existence error' do
        invalid_channel = 'InvalidChannel'
        # Mock the private validation method to raise error with channel name
        allow(described_class).to receive(:validate_channel_exists!).with(invalid_channel)
          .and_raise(ArgumentError, "Channel InvalidChannel does not exist")
        
        expect {
          described_class.validate!(invalid_channel, target, data)
        }.to raise_error(ArgumentError, /Channel InvalidChannel does not exist/)
      end
    end
  end
end