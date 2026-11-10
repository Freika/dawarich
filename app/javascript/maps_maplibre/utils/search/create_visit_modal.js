import { formatDate, formatDateTime, translate } from "i18n"

/**
 * Creating a visit from a search result: the modal and its submit.
 * Mixed into the controller; `this` is the controller.
 */
export const createVisitModal = {
  openCreateVisitModal(visitData) {
    // Create modal HTML
    const modalId = "create-visit-modal"

    // Remove existing modal if present
    const existingModal = document.getElementById(modalId)
    if (existingModal) {
      existingModal.remove()
    }

    const modal = document.createElement("div")
    modal.id = modalId
    modal.innerHTML = `
      <input type="checkbox" id="${modalId}-toggle" class="modal-toggle" checked />
      <div class="modal" role="dialog">
        <div class="modal-box">
          <h3 class="text-lg font-bold mb-4">${translate("visits.create")}</h3>

          <form id="${modalId}-form">
            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">${translate("common.name")}</span>
              </label>
              <input type="text" name="name" class="input input-bordered w-full"
                     value="${this.escapeHtml(visitData.name)}" required />
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">${translate("visits.start_time")}</span>
              </label>
              <input type="datetime-local" name="started_at" class="input input-bordered w-full"
                     max="9999-12-31T23:59" value="${this.formatDateTimeForInput(visitData.started_at)}" required />
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">${translate("visits.end_time")}</span>
              </label>
              <input type="datetime-local" name="ended_at" class="input input-bordered w-full"
                     max="9999-12-31T23:59" value="${this.formatDateTimeForInput(visitData.ended_at)}" required />
            </div>

            <input type="hidden" name="latitude" value="${visitData.latitude}" />
            <input type="hidden" name="longitude" value="${visitData.longitude}" />

            <div class="modal-action">
              <button type="button" class="btn" data-action="close">${translate("common.cancel")}</button>
              <button type="submit" class="btn btn-primary">
                <span class="submit-text">${translate("visits.create")}</span>
                <span class="loading loading-spinner loading-sm hidden"></span>
              </button>
            </div>
          </form>
        </div>
        <label class="modal-backdrop" for="${modalId}-toggle"></label>
      </div>
    `

    document.body.appendChild(modal)

    // Attach event listeners
    const form = modal.querySelector("form")
    const closeBtn = modal.querySelector('[data-action="close"]')
    const modalToggle = modal.querySelector(`#${modalId}-toggle`)
    const backdrop = modal.querySelector(".modal-backdrop")

    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitCreateVisit(form, modal)
    })

    closeBtn.addEventListener("click", () => {
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)
    })

    backdrop.addEventListener("click", () => {
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)
    })
  },

  /**
   * Submit create visit form
   * @param {HTMLFormElement} form - Form element
   * @param {HTMLElement} modal - Modal element
   */
  async submitCreateVisit(form, modal) {
    const submitBtn = form.querySelector('button[type="submit"]')
    const submitText = submitBtn.querySelector(".submit-text")
    const spinner = submitBtn.querySelector(".loading")

    // Disable submit button and show loading
    submitBtn.disabled = true
    submitText.classList.add("hidden")
    spinner.classList.remove("hidden")

    try {
      const formData = new FormData(form)
      const visitData = {
        name: formData.get("name"),
        latitude: parseFloat(formData.get("latitude")),
        longitude: parseFloat(formData.get("longitude")),
        started_at: formData.get("started_at"),
        ended_at: formData.get("ended_at"),
        status: "confirmed",
      }

      const response = await this.service.createVisit(visitData)

      if (response.error) {
        throw new Error(response.error)
      }

      // Success - close modal and show success message
      const modalToggle = modal.querySelector(".modal-toggle")
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)

      // Show success notification
      this.showSuccessNotification(translate("visits.created_without_name"))

      // Dispatch custom event for other components to react
      document.dispatchEvent(
        new CustomEvent("visit:created", {
          detail: {
            visit: response,
            coordinates: [visitData.longitude, visitData.latitude],
          },
        }),
      )
    } catch (error) {
      console.error("Failed to create visit:", error)
      this.showError(
        translate("visits.create_failed_with_error", { error: error.message }),
      )

      // Re-enable submit button
      submitBtn.disabled = false
      submitText.classList.remove("hidden")
      spinner.classList.add("hidden")
    }
  },

  /**
   * Show success notification
   * @param {string} message - Success message
   */
  showSuccessNotification(message) {
    const notification = document.createElement("div")
    notification.className = "toast toast-top toast-end z-[9999]"
    notification.innerHTML = `
      <div class="alert alert-success">
        <span>✓ ${this.escapeHtml(message)}</span>
      </div>
    `
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 3000)
  },

  /**
   * Format datetime for input field (YYYY-MM-DDTHH:MM)
   * @param {string} dateString - Date string
   * @returns {string} Formatted datetime
   */
  formatDateTimeForInput(dateString) {
    const date = new Date(dateString)
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const minutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  },

  /**
   * Format date in short format
   * @param {string} dateString - Date string
   * @returns {string} Formatted date
   */
  formatDateShort(dateString) {
    return formatDate(dateString)
  },

  /**
   * Format date and time
   * @param {string} dateString - Date string
   * @returns {string} Formatted date and time
   */
  formatDateTime(dateString) {
    return formatDateTime(dateString)
  },

  /**
   * Escape HTML to prevent XSS
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
}
