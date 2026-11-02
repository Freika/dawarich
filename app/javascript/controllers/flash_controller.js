import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

const ALERT_CLASSES = {
  error: "alert-error",
  alert: "alert-error",
  notice: "alert-info",
  info: "alert-info",
  success: "alert-success",
  warning: "alert-warning",
}

const ICON_PATHS = {
  error: "M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z",
  alert: "M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z",
  success: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
  warning:
    "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
  notice: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
  info: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
}

const CLOSE_PATH = "M6 18L18 6M6 6l12 12"

export default class extends Controller {
  static targets = ["message", "dismissAll"]

  connect() {
    this.updateDismissAll()
  }

  messageTargetConnected() {
    this.updateDismissAll()
  }

  messageTargetDisconnected() {
    this.updateDismissAll()
  }

  dismissAll() {
    for (const message of this.messageTargets) message.remove()
  }

  updateDismissAll() {
    if (this.hasDismissAllTarget) {
      this.dismissAllTarget.hidden = this.messageTargets.length < 2
    }
  }

  static show(type, message) {
    const container = document.getElementById("flash-messages")
    if (!container) return

    const alertClass = ALERT_CLASSES[type] || "alert-info"
    const iconPath = ICON_PATHS[type] || ICON_PATHS.info
    const autoRemove = type === "notice" || type === "success"

    const div = document.createElement("div")
    div.setAttribute("data-flash-target", "message")
    div.setAttribute("data-controller", "removals")
    div.setAttribute("data-removals-timeout-value", autoRemove ? "5000" : "0")
    div.setAttribute("role", "alert")
    div.className = `alert ${alertClass} flash-message`
    div.innerHTML = `
      <div class="flash-message__body">
        <span class="flash-message__icon" aria-hidden="true">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="${iconPath}" />
          </svg>
        </span>
        <span class="flash-message__text"></span>
      </div>
      <button type="button" data-action="click->removals#remove" class="btn btn-sm btn-square btn-ghost flash-message__close">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="${CLOSE_PATH}" />
        </svg>
      </button>
    `
    div
      .querySelector("button")
      .setAttribute("aria-label", translate("common.close"))
    // Set message text safely (no innerHTML for user content)
    div.querySelector(".flash-message__text").textContent = message

    container.appendChild(div)
  }
}
