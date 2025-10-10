# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::CoreBroadcastService, type: :service do
  let(:sync_session) { create(:sync_session) }
  let(:test_data) { { status: 'processing', processed: 10, total: 100 } }

  describe '#initialize' do
    it 'sets instance variables correctly' do
      service = described_class.new(
        channel: SyncStatusChannel,
        target: sync_session,
        data: test_data
      )

      expect(service.channel).to eq(SyncStatusChannel)
      expect(service.target).to eq(sync_session)
      expect(service.data).to eq(test_data)
    end
  end

  describe '#broadcast' do
    let(:service) do
      described_class.new(
        channel: SyncStatusChannel,
        target: sync_session,
        data: test_data
      )
    end

    context 'when broadcast succeeds' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to)
      end

      it 'returns true' do
        result = service.broadcast
        expect(result).to be true
      end

      it 'calls broadcast_to with correct parameters' do
        service.broadcast
        expect(SyncStatusChannel).to have_received(:broadcast_to).with(sync_session, test_data)
      end
    end

    context 'when broadcast fails' do
      before do
        allow(SyncStatusChannel).to receive(:broadcast_to).and_raise(StandardError, 'Connection failed')
      end

      it 'raises BroadcastError' do
        expect { service.broadcast }.to raise_error(Services::CoreBroadcastService::BroadcastError, /Broadcast failed: Connection failed/)
      end
    end

    context 'with string channel name' do
      let(:service) do
        described_class.new(
          channel: 'SyncStatusChannel',
          target: sync_session,
          data: test_data
        )
      end

      before do
        allow(SyncStatusChannel).to receive(:broadcast_to)
      end

      it 'resolves channel name to class and broadcasts' do
        result = service.broadcast
        expect(result).to be true
        expect(SyncStatusChannel).to have_received(:broadcast_to).with(sync_session, test_data)
      end
    end

    context 'with invalid channel name' do
      let(:service) do
        described_class.new(
          channel: 'NonExistentChannel',
          target: sync_session,
          data: test_data
        )
      end

      it 'raises BroadcastError' do
        expect { service.broadcast }.to raise_error(Services::CoreBroadcastService::BroadcastError, /Invalid channel name/)
      end
    end

    context 'with invalid inputs' do
      it 'raises ArgumentError for nil channel' do
        expect {
          described_class.new(channel: nil, target: sync_session, data: test_data)
        }.to raise_error(ArgumentError, /Channel cannot be nil/)
      end

      it 'raises ArgumentError for nil target' do
        expect {
          described_class.new(channel: SyncStatusChannel, target: nil, data: test_data)
        }.to raise_error(ArgumentError, /Target cannot be nil/)
      end

      it 'raises ArgumentError for nil data' do
        expect {
          described_class.new(channel: SyncStatusChannel, target: sync_session, data: nil)
        }.to raise_error(ArgumentError, /Data cannot be nil/)
      end
    end
  end
end
