import { Controller } from "@hotwired/stimulus"

/**
 * SyncStatusIndicatorController — Lightweight read-only controller for the
 * collapsed sync status indicator in the dashboard header.
 *
 * Reads initial state from data attributes. No polling, no WebSocket.
 * Future enhancement: subscribe to ActionCable for real-time updates.
 */
export default class extends Controller {
  static values = {
    active: { type: Boolean, default: false },
    lastSync: { type: String, default: "" }
  }
}
