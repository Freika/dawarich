// This controller is being used on:
// - trips/new
// - trips/edit

import { translate } from "i18n"
import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["startedAt", "endedAt"]
  static values = { tripsId: String }

  connect() {
    console.log("Datetime controller connected")
    this.debounceTimer = null

    // Add validation listeners
    if (this.hasStartedAtTarget && this.hasEndedAtTarget) {
      // Validate on change to set validation state
      this.startedAtTarget.addEventListener("change", () =>
        this.validateDates(),
      )
      this.endedAtTarget.addEventListener("change", () => this.validateDates())

      // Validate on blur to set validation state
      this.startedAtTarget.addEventListener("blur", () => this.validateDates())
      this.endedAtTarget.addEventListener("blur", () => this.validateDates())

      // Add form submit validation
      const form = this.element.closest("form")
      if (form) {
        form.addEventListener("submit", (e) => {
          if (!this.validateDates()) {
            e.preventDefault()
            this.endedAtTarget.reportValidity()
          }
        })
      }
    }
  }

  validateDates(showPopup = false) {
    const startDate = new Date(this.startedAtTarget.value)
    const endDate = new Date(this.endedAtTarget.value)

    // Clear any existing custom validity
    this.startedAtTarget.setCustomValidity("")
    this.endedAtTarget.setCustomValidity("")

    // Check if both dates are valid
    if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
      return true
    }

    // Validate that start date is before end date
    if (startDate >= endDate) {
      const errorMessage = translate("datetime.start_before_end")
      this.endedAtTarget.setCustomValidity(errorMessage)
      if (showPopup) {
        this.endedAtTarget.reportValidity()
      }
      return false
    }

    return true
  }

  updateCoordinates() {
    clearTimeout(this.debounceTimer)

    this.debounceTimer = setTimeout(() => {
      const startAt = this.startedAtTarget.value
      const endAt = this.endedAtTarget.value
      if (!startAt || !endAt || !this.validateDates(false)) return

      document
        .querySelector('[data-controller~="trip-maplibre-preview"]')
        ?.dispatchEvent(
          new CustomEvent("trip-range-updated", {
            detail: { startAt, endAt },
          }),
        )
    }, 500)
  }
}
