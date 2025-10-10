# frozen_string_literal: true

# CoreBroadcastService provides the core broadcasting functionality with a single responsibility.
# This service is focused only on performing the actual ActionCable broadcast operation.
#
# This is part of the architectural refactor to separate concerns from the monolithic
# BroadcastReliabilityService into focused, testable components.
#
# Usage:
#   service = CoreBroadcastService.new(
#     channel: SyncStatusChannel,
#     target: sync_session,
#     data: { status: 'processing' }
#   )
#   result = service.broadcast
#
module Services
  class CoreBroadcastService
  class BroadcastError < StandardError; end

  attr_reader :channel, :target, :data

  def initialize(channel:, target:, data:)
    @channel = channel
    @target = target
    @data = data
    validate_inputs!
  end

  # Perform the ActionCable broadcast
  # @return [Boolean] Success status
  def broadcast
    channel_class = resolve_channel_class
    channel_class.broadcast_to(target, data)

    true
  rescue StandardError => e
    raise BroadcastError, "Broadcast failed: #{e.message}"
  end

  private

  # Validate inputs before broadcasting
  def validate_inputs!
    raise ArgumentError, "Channel cannot be nil" if channel.nil?
    raise ArgumentError, "Target cannot be nil" if target.nil?
    raise ArgumentError, "Data cannot be nil" if data.nil?
    raise ArgumentError, "Target must respond to id" unless target.respond_to?(:id)
  end

  # Resolve channel class from string or class
  # @return [Class] Channel class
  def resolve_channel_class
    case channel
    when String
      channel.constantize
    when Class
      channel
    else
      raise ArgumentError, "Channel must be a String or Class, got #{channel.class}"
    end
  rescue NameError => e
    raise BroadcastError, "Invalid channel name '#{channel}': #{e.message}"
  end
  end
end
