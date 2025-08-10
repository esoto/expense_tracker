# frozen_string_literal: true

# ActionCable channel for real-time queue status updates
class QueueChannel < ApplicationCable::Channel
  def subscribed
    stream_from "queue_updates"
    Rails.logger.info "Client subscribed to queue updates channel"
  end

  def unsubscribed
    Rails.logger.info "Client unsubscribed from queue updates channel"
  end
end