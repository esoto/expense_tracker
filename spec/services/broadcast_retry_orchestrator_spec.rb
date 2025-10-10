# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::BroadcastRetryOrchestrator, type: :service do
  let(:sync_session) { create(:sync_session) }
  let(:test_data) { { status: 'processing', processed: 10, total: 100 } }
  let(:broadcaster) do
    CoreBroadcastService.new(
      channel: SyncStatusChannel,
      target: sync_session,
      data: test_data
    )
  end
  let(:analytics) { double('Analytics') }
  let(:error_handler) { double('ErrorHandler') }

  describe '#initialize' do
    it 'sets dependencies correctly' do
      orchestrator = described_class.new(
        broadcaster: broadcaster,
        analytics: analytics,
        error_handler: error_handler
      )

      expect(orchestrator.broadcaster).to eq(broadcaster)
      expect(orchestrator.analytics).to eq(analytics)
      expect(orchestrator.error_handler).to eq(error_handler)
    end

    it 'uses null objects when dependencies not provided' do
      orchestrator = described_class.new(broadcaster: broadcaster)

      expect(orchestrator.analytics).to be_a(described_class::NullAnalytics)
      expect(orchestrator.error_handler).to be_a(described_class::NullErrorHandler)
    end
  end

  describe '#broadcast_with_retry' do
    let(:orchestrator) do
      described_class.new(
        broadcaster: broadcaster,
        analytics: analytics,
        error_handler: error_handler
      )
    end

    before do
      allow(analytics).to receive(:record_success)
      allow(analytics).to receive(:record_failure)
      allow(error_handler).to receive(:handle_final_failure)
      allow(orchestrator).to receive(:sleep) # Mock sleep to speed up tests
    end

    context 'when broadcast succeeds on first attempt' do
      before do
        allow(broadcaster).to receive(:broadcast).and_return(true)
      end

      it 'returns true' do
        result = orchestrator.broadcast_with_retry(priority: :medium)
        expect(result).to be true
      end

      it 'records success analytics' do
        orchestrator.broadcast_with_retry(priority: :medium)

        expect(analytics).to have_received(:record_success).with(
          channel: 'SyncStatusChannel',
          target_type: 'SyncSession',
          target_id: sync_session.id,
          priority: :medium,
          attempt: 1,
          duration: be_a(Float)
        )
      end
    end

    context 'when broadcast fails but succeeds on retry' do
      before do
        call_count = 0
        allow(broadcaster).to receive(:broadcast) do
          call_count += 1
          if call_count == 1
            raise CoreBroadcastService::BroadcastError, 'Temporary failure'
          else
            true
          end
        end
      end

      it 'retries and eventually succeeds' do
        result = orchestrator.broadcast_with_retry(priority: :medium)
        expect(result).to be true
      end

      it 'records failure and then success' do
        orchestrator.broadcast_with_retry(priority: :medium)

        expect(analytics).to have_received(:record_failure).once
        expect(analytics).to have_received(:record_success).once
      end
    end

    context 'when broadcast fails all attempts' do
      before do
        allow(broadcaster).to receive(:broadcast)
          .and_raise(CoreBroadcastService::BroadcastError, 'Persistent failure')
      end

      it 'exhausts retries and returns false' do
        result = orchestrator.broadcast_with_retry(priority: :medium)
        expect(result).to be false
      end

      it 'records failures for all attempts' do
        orchestrator.broadcast_with_retry(priority: :medium)

        # Medium priority has 3 max retries
        expect(analytics).to have_received(:record_failure).exactly(3).times
      end

      it 'calls error handler for final failure' do
        orchestrator.broadcast_with_retry(priority: :medium)

        expect(error_handler).to have_received(:handle_final_failure).with(
          broadcaster.channel,
          broadcaster.target,
          broadcaster.data,
          :medium,
          be_a(CoreBroadcastService::BroadcastError)
        )
      end
    end

    context 'with different priority levels' do
      before do
        allow(broadcaster).to receive(:broadcast)
          .and_raise(CoreBroadcastService::BroadcastError, 'Failure')
      end

      it 'uses correct retry count for critical priority' do
        orchestrator.broadcast_with_retry(priority: :critical)
        expect(analytics).to have_received(:record_failure).exactly(5).times
      end

      it 'uses correct retry count for high priority' do
        orchestrator.broadcast_with_retry(priority: :high)
        expect(analytics).to have_received(:record_failure).exactly(4).times
      end

      it 'uses correct retry count for low priority' do
        orchestrator.broadcast_with_retry(priority: :low)
        expect(analytics).to have_received(:record_failure).exactly(2).times
      end
    end

    context 'with invalid priority' do
      it 'raises ArgumentError' do
        expect {
          orchestrator.broadcast_with_retry(priority: :invalid)
        }.to raise_error(ArgumentError, /Invalid priority 'invalid'/)
      end
    end
  end

  describe 'null objects' do
    describe 'NullAnalytics' do
      it 'responds to analytics methods without error' do
        null_analytics = described_class::NullAnalytics.new

        expect { null_analytics.record_success }.not_to raise_error
        expect { null_analytics.record_failure }.not_to raise_error
      end
    end

    describe 'NullErrorHandler' do
      it 'responds to error handler methods without error' do
        null_handler = described_class::NullErrorHandler.new

        expect { null_handler.handle_final_failure }.not_to raise_error
      end
    end
  end
end
