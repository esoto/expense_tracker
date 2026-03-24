// Shared helper to create undo notification elements.
// Used by inline_actions_controller and dashboard_inline_actions_controller
// to show undo notifications after AJAX deletes.
//
// Uses DOM APIs (textContent, setAttribute) instead of innerHTML to prevent XSS.

export function createUndoNotification(undoId, timeRemaining, message) {
  // Remove any existing undo notification
  document.querySelector(".undo-notification")?.remove()

  const notification = document.createElement("div")
  notification.className = "undo-notification slide-in-bottom pointer-events-auto"
  notification.setAttribute("data-controller", "undo-manager")
  notification.setAttribute("data-undo-manager-undo-id-value", undoId)
  notification.setAttribute("data-undo-manager-time-remaining-value", timeRemaining || 30)
  notification.setAttribute("role", "alert")
  notification.setAttribute("aria-live", "polite")

  // Progress bar
  const progress = document.createElement("div")
  progress.className = "undo-notification-progress"
  const progressBar = document.createElement("div")
  progressBar.className = "undo-notification-progress-bar"
  progressBar.setAttribute("data-undo-manager-target", "progressBar")
  progress.appendChild(progressBar)

  // Body
  const body = document.createElement("div")
  body.className = "undo-notification-body"

  // Content (icon + text)
  const content = document.createElement("div")
  content.className = "undo-notification-content"

  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  icon.setAttribute("class", "undo-notification-icon")
  icon.setAttribute("fill", "none")
  icon.setAttribute("stroke", "currentColor")
  icon.setAttribute("viewBox", "0 0 24 24")
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
  path.setAttribute("stroke-linecap", "round")
  path.setAttribute("stroke-linejoin", "round")
  path.setAttribute("stroke-width", "2")
  path.setAttribute("d", "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16")
  icon.appendChild(path)

  const textWrap = document.createElement("div")
  textWrap.className = "undo-notification-text"

  const msg = document.createElement("p")
  msg.className = "undo-notification-message"
  msg.setAttribute("data-undo-manager-target", "message")
  msg.textContent = message || "Gasto eliminado"

  const timer = document.createElement("p")
  timer.className = "undo-notification-timer"
  const timerSpan = document.createElement("span")
  timerSpan.setAttribute("data-undo-manager-target", "timer")
  timer.appendChild(timerSpan)
  timer.appendChild(document.createTextNode(" para deshacer"))

  textWrap.appendChild(msg)
  textWrap.appendChild(timer)
  content.appendChild(icon)
  content.appendChild(textWrap)

  // Actions
  const actions = document.createElement("div")
  actions.className = "undo-notification-actions"

  const undoBtn = document.createElement("button")
  undoBtn.className = "undo-notification-undo-btn"
  undoBtn.setAttribute("data-undo-manager-target", "undoButton")
  undoBtn.setAttribute("data-action", "click->undo-manager#undo")
  undoBtn.setAttribute("aria-label", "Deshacer eliminación")
  undoBtn.textContent = "Deshacer"

  const dismissBtn = document.createElement("button")
  dismissBtn.className = "undo-notification-dismiss-btn"
  dismissBtn.setAttribute("data-action", "click->undo-manager#dismiss")
  dismissBtn.setAttribute("aria-label", "Cerrar notificación")
  const dismissIcon = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  dismissIcon.setAttribute("width", "16")
  dismissIcon.setAttribute("height", "16")
  dismissIcon.setAttribute("fill", "none")
  dismissIcon.setAttribute("stroke", "currentColor")
  dismissIcon.setAttribute("viewBox", "0 0 24 24")
  const dismissPath = document.createElementNS("http://www.w3.org/2000/svg", "path")
  dismissPath.setAttribute("stroke-linecap", "round")
  dismissPath.setAttribute("stroke-linejoin", "round")
  dismissPath.setAttribute("stroke-width", "2")
  dismissPath.setAttribute("d", "M6 18L18 6M6 6l12 12")
  dismissIcon.appendChild(dismissPath)
  dismissBtn.appendChild(dismissIcon)

  actions.appendChild(undoBtn)
  actions.appendChild(dismissBtn)

  body.appendChild(content)
  body.appendChild(actions)

  notification.appendChild(progress)
  notification.appendChild(body)

  document.body.appendChild(notification)
}
