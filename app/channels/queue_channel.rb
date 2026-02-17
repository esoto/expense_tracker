# frozen_string_literal: true

# ActionCable channel for real-time queue status updates.
# Streams are scoped to the user's session ID to prevent cross-user data leakage.
class QueueChannel < ApplicationCable::Channel
  def subscribed
    session_id = current_session_info[:session_id]

    if session_id.blank?
      reject
      return
    end

    stream_from self.class.stream_name_for(session_id)
    truncated_id = session_id.to_s[0, 5]
    Rails.logger.info "Client subscribed to queue updates channel (session: #{truncated_id}...)"
  end

  def unsubscribed
    Rails.logger.info "Client unsubscribed from queue updates channel"
  end

  # Generate the session-scoped stream name for broadcasting.
  # Used by both the channel (for subscribing) and controllers (for broadcasting).
  def self.stream_name_for(session_id)
    return nil if session_id.blank?

    "queue_updates_#{session_id}"
  end
end
