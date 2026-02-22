import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static targets = [
    "form",
    "checkbox",
    "enabledField",
    "durationField",
    "durationContainer",
    "durationSelect",
    "expirationInfo",
  ]
  static values = {
    memberId: Number,
    enabled: Boolean,
    expiresAt: String,
  }

  connect() {
    this.setupExpirationTimer()
  }

  disconnect() {
    this.clearExpirationTimer()
  }

  toggle() {
    const newState = !this.enabledValue
    this.enabledFieldTarget.value = newState ? "true" : "false"

    // Update duration field from select if available
    if (this.hasDurationSelectTarget) {
      this.durationFieldTarget.value = this.durationSelectTarget.value
    }

    this.formTarget.requestSubmit()
  }

  changeDuration() {
    if (!this.enabledValue) return

    this.durationFieldTarget.value = this.durationSelectTarget.value
    this.enabledFieldTarget.value = "true"
    this.formTarget.requestSubmit()
  }

  // --- Timer / Countdown (client-side only) ---

  setupExpirationTimer() {
    this.clearExpirationTimer()

    if (!this.enabledValue || !this.expiresAtValue) return

    const expiresAt = new Date(this.expiresAtValue)
    const msUntilExpiration = expiresAt.getTime() - Date.now()

    if (msUntilExpiration <= 0) return

    this.expirationTimer = setTimeout(() => {
      this.enabledValue = false
      if (this.hasCheckboxTarget) this.checkboxTarget.checked = false
      if (this.hasDurationContainerTarget)
        this.durationContainerTarget.classList.add("hidden")
      Flash.show("info", "Location sharing has expired")

      document.dispatchEvent(
        new CustomEvent("location-sharing:expired", {
          detail: { userId: this.memberIdValue },
        }),
      )
    }, msUntilExpiration)

    this.updateExpirationCountdown()
    this.countdownInterval = setInterval(() => {
      this.updateExpirationCountdown()
    }, 60000)
  }

  clearExpirationTimer() {
    if (this.expirationTimer) {
      clearTimeout(this.expirationTimer)
      this.expirationTimer = null
    }
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
      this.countdownInterval = null
    }
  }

  updateExpirationCountdown() {
    if (!this.hasExpirationInfoTarget || !this.expiresAtValue) return

    const expiresAt = new Date(this.expiresAtValue)
    const msRemaining = expiresAt.getTime() - Date.now()

    if (msRemaining <= 0) {
      this.expirationInfoTarget.textContent = "Expired"
      this.expirationInfoTarget.classList.remove("hidden")
      return
    }

    const hoursLeft = Math.floor(msRemaining / (1000 * 60 * 60))
    const minutesLeft = Math.floor(
      (msRemaining % (1000 * 60 * 60)) / (1000 * 60),
    )

    const timeText =
      hoursLeft > 0
        ? `${hoursLeft}h ${minutesLeft}m remaining`
        : `${minutesLeft}m remaining`

    this.expirationInfoTarget.textContent = `Expires in ${timeText}`
    this.expirationInfoTarget.classList.remove("hidden")
  }
}
