import { Controller } from "@hotwired/stimulus"
import { Toast } from "maps_maplibre/components/toast"

/**
 * Controller for visit creation modal in Maps V2
 */
export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "modalTitle",
    "nameInput",
    "startTimeInput",
    "endTimeInput",
    "latitudeInput",
    "longitudeInput",
    "submitButton",
  ]

  static values = {
    apiKey: String,
  }

  connect() {
    console.log("[Visit Creation V2] Controller connected")
    this.marker = null
    this.mapController = null
    this.editingVisitId = null
    this.setupEventListeners()
  }

  setupEventListeners() {
    document.addEventListener("visit:edit", (e) => {
      this.openForEdit(e.detail.visit)
    })
  }

  disconnect() {
    this.cleanup()
  }

  /**
   * Open the modal with coordinates
   */
  open(lat, lng, mapController) {
    console.log("[Visit Creation V2] Opening modal", { lat, lng })

    this.editingVisitId = null
    this.mapController = mapController
    this.latitudeInputTarget.value = lat
    this.longitudeInputTarget.value = lng

    // Set modal title and button for creation
    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = "Create New Visit"
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = "Create Visit"
    }

    // Set default times
    const now = new Date()
    const oneHourLater = new Date(now.getTime() + 60 * 60 * 1000)

    this.startTimeInputTarget.value = this.formatDateTime(now)
    this.endTimeInputTarget.value = this.formatDateTime(oneHourLater)

    // Show modal
    this.modalTarget.classList.add("modal-open")

    // Focus on name input
    setTimeout(() => this.nameInputTarget.focus(), 100)

    // Add marker to map
    this.addMarker(lat, lng)
  }

  /**
   * Open the modal for editing an existing visit
   */
  openForEdit(visit) {
    console.log("[Visit Creation V2] Opening modal for edit", visit)

    this.editingVisitId = visit.id

    // Set modal title and button for editing
    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = "Edit Visit"
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = "Update Visit"
    }

    // Fill form with visit data
    this.nameInputTarget.value = visit.name || ""
    this.latitudeInputTarget.value = visit.latitude
    this.longitudeInputTarget.value = visit.longitude

    // Convert timestamps to datetime-local format
    this.startTimeInputTarget.value = this.formatDateTime(
      new Date(visit.started_at),
    )
    this.endTimeInputTarget.value = this.formatDateTime(
      new Date(visit.ended_at),
    )

    // Show modal
    this.modalTarget.classList.add("modal-open")

    // Focus on name input
    setTimeout(() => this.nameInputTarget.focus(), 100)

    // Try to get map controller from the maps--maplibre controller
    const mapElement = document.querySelector(
      '[data-controller*="maps--maplibre"]',
    )
    if (mapElement) {
      const app = window.Stimulus || window.Application
      this.mapController = app?.getControllerForElementAndIdentifier(
        mapElement,
        "maps--maplibre",
      )
    }

    // Add marker to map
    this.addMarker(visit.latitude, visit.longitude)
  }

  /**
   * Close the modal
   */
  close() {
    console.log("[Visit Creation V2] Closing modal")

    // Hide modal
    this.modalTarget.classList.remove("modal-open")

    // Reset form
    this.formTarget.reset()

    // Reset editing state
    this.editingVisitId = null

    // Remove marker
    this.removeMarker()
  }

  /**
   * Handle form submission
   */
  async submit(event) {
    event.preventDefault()

    const isEdit = this.editingVisitId !== null
    console.log(
      `[Visit Creation V2] Submitting form (${isEdit ? "edit" : "create"})`,
    )

    const formData = new FormData(this.formTarget)

    const visitData = {
      visit: {
        name: formData.get("name"),
        started_at: formData.get("started_at"),
        ended_at: formData.get("ended_at"),
        latitude: parseFloat(formData.get("latitude")),
        longitude: parseFloat(formData.get("longitude")),
        status: "confirmed",
      },
    }

    try {
      const url = isEdit
        ? `/api/v1/visits/${this.editingVisitId}`
        : "/api/v1/visits"
      const method = isEdit ? "PATCH" : "POST"

      const response = await fetch(url, {
        method: method,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
          "X-CSRF-Token":
            document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify(visitData),
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(
          errorData.error || `Failed to ${isEdit ? "update" : "create"} visit`,
        )
      }

      const visit = await response.json()

      console.log(
        `[Visit Creation V2] Visit ${isEdit ? "updated" : "created"} successfully`,
        visit,
      )

      // Show success message
      this.showToast(
        `Visit ${isEdit ? "updated" : "created"} successfully`,
        "success",
      )

      // Close modal
      this.close()

      // Dispatch event to notify map controller
      const eventName = isEdit ? "visit:updated" : "visit:created"
      document.dispatchEvent(
        new CustomEvent(eventName, {
          detail: { visit },
        }),
      )
    } catch (error) {
      console.error(
        `[Visit Creation V2] Error ${isEdit ? "updating" : "creating"} visit:`,
        error,
      )
      this.showToast(
        error.message || `Failed to ${isEdit ? "update" : "create"} visit`,
        "error",
      )
    }
  }

  /**
   * Add marker to map
   */
  addMarker(lat, lng) {
    if (!this.mapController) return

    // Remove existing marker if any
    this.removeMarker()

    // Create marker element
    const el = document.createElement("div")
    el.className = "visit-creation-marker"
    el.innerHTML = "📍"
    el.style.fontSize = "30px"

    // Use maplibregl if available (from mapController)
    const maplibregl = window.maplibregl
    if (maplibregl) {
      this.marker = new maplibregl.Marker({ element: el })
        .setLngLat([lng, lat])
        .addTo(this.mapController.map)
    }
  }

  /**
   * Remove marker from map
   */
  removeMarker() {
    if (this.marker) {
      this.marker.remove()
      this.marker = null
    }
  }

  /**
   * Clean up resources
   */
  cleanup() {
    this.removeMarker()
  }

  /**
   * Format date for datetime-local input
   */
  formatDateTime(date) {
    return date.toISOString().slice(0, 16)
  }

  /**
   * Show toast notification
   */
  showToast(message, type = "info") {
    Toast[type](message)
  }
}
