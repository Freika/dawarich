// This controller is being used on:
// - trips/new
// - trips/edit

import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["startedAt", "endedAt", "apiKey"]
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
      const errorMessage = "Start date must be earlier than end date"
      this.endedAtTarget.setCustomValidity(errorMessage)
      if (showPopup) {
        this.endedAtTarget.reportValidity()
      }
      return false
    }

    return true
  }

  async updateCoordinates() {
    // Clear any existing timeout
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    // Set new timeout
    this.debounceTimer = setTimeout(async () => {
      const startedAt = this.startedAtTarget.value
      const endedAt = this.endedAtTarget.value
      const apiKey = this.apiKeyTarget.value

      // Validate dates before making API call (don't show popup, already shown on change)
      if (!this.validateDates(false)) {
        return
      }

      if (startedAt && endedAt) {
        try {
          const params = new URLSearchParams({
            start_at: startedAt,
            end_at: endedAt,
            api_key: apiKey,
            slim: true,
          })
          let allPoints = []
          let currentPage = 1
          const perPage = 1000

          let hasMorePages = true
          while (hasMorePages) {
            const paginatedParams = `${params}&page=${currentPage}&per_page=${perPage}`
            const response = await fetch(`/api/v1/points?${paginatedParams}`)
            const data = await response.json()

            allPoints = [...allPoints, ...data]

            const totalPages = parseInt(
              response.headers.get("X-Total-Pages"),
              10,
            )
            currentPage++

            hasMorePages = totalPages && currentPage <= totalPages
          }

          const event = new CustomEvent("coordinates-updated", {
            detail: { coordinates: allPoints },
            bubbles: true,
            composed: true,
          })

          const tripsElement = document.querySelector(
            '[data-controller="trips"]',
          )
          if (tripsElement) {
            tripsElement.dispatchEvent(event)
          } else {
            console.error("Trips controller element not found")
          }
        } catch (error) {
          console.error("Error:", error)
        }
      }
    }, 500)
  }
}
