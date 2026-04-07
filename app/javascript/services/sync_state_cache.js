/**
 * SyncStateCache — sessionStorage-backed state caching for sync sessions.
 *
 * Provides simple read/write/clear operations with a 5-minute staleness guard.
 * The widget controller calls these directly; DOM side-effects (showCacheIndicator)
 * stay in the controller since they require access to the DOM.
 */
export class SyncStateCache {
  static CACHE_TTL_MS = 5 * 60 * 1000 // 5 minutes

  /**
   * Write session state to sessionStorage.
   * @param {number|string} sessionId
   * @param {object} data  — raw update payload from the server
   */
  static cacheState(sessionId, data) {
    const cacheKey = `sync_state_${sessionId}`
    const cacheData = {
      ...data,
      timestamp: Date.now(),
      sessionId
    }

    try {
      sessionStorage.setItem(cacheKey, JSON.stringify(cacheData))
    } catch (error) {
      console.error('[SyncStateCache] Error caching state', error)
    }
  }

  /**
   * Read cached state. Returns null when missing or stale (> 5 minutes old).
   * @param {number|string} sessionId
   * @returns {object|null}
   */
  static loadCachedState(sessionId) {
    const cacheKey = `sync_state_${sessionId}`

    try {
      const raw = sessionStorage.getItem(cacheKey)
      if (!raw) return null

      const data = JSON.parse(raw)
      const age = Date.now() - data.timestamp

      if (age < SyncStateCache.CACHE_TTL_MS) {
        return data
      }

      // Stale — remove automatically
      SyncStateCache.clearCachedState(sessionId)
      return null
    } catch (error) {
      console.error('[SyncStateCache] Error loading cached state', error)
      return null
    }
  }

  /**
   * Remove a session's cached state from sessionStorage.
   * @param {number|string} sessionId
   */
  static clearCachedState(sessionId) {
    const cacheKey = `sync_state_${sessionId}`

    try {
      sessionStorage.removeItem(cacheKey)
    } catch (error) {
      console.error('[SyncStateCache] Error clearing cache', error)
    }
  }
}
