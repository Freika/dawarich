import { Controller } from '@hotwired/stimulus'
import { Toast } from 'maps_v2/components/toast'

/**
 * Controller for visit creation modal in Maps V2
 */
export default class extends Controller {
  static targets = [
    'modal',
    'form',
    'modalTitle',
    'nameInput',
    'startTimeInput',
    'endTimeInput',
    'latitudeInput',
    'longitudeInput',
    'locationDisplay',
    'submitButton',
    'submitSpinner',
    'submitText'
  ]

  static values = {
    apiKey: String
  }

  connect() {
    console.log('[Visit Creation V2] Controller connected')
    this.marker = null
    this.mapController = null
    this.adjustingLocation = false
  }

  disconnect() {
    this.cleanup()
  }

  /**
   * Open the modal with coordinates
   */
  open(lat, lng, mapController) {
    console.log('[Visit Creation V2] Opening modal', { lat, lng })

    this.mapController = mapController
    this.latitudeInputTarget.value = lat
    this.longitudeInputTarget.value = lng

    // Set default times
    const now = new Date()
    const oneHourLater = new Date(now.getTime() + (60 * 60 * 1000))

    this.startTimeInputTarget.value = this.formatDateTime(now)
    this.endTimeInputTarget.value = this.formatDateTime(oneHourLater)

    // Update location display
    this.updateLocationDisplay()

    // Show modal
    this.modalTarget.classList.add('modal-open')

    // Focus on name input
    setTimeout(() => this.nameInputTarget.focus(), 100)

    // Add marker to map
    this.addMarker(lat, lng)
  }

  /**
   * Close the modal
   */
  close() {
    console.log('[Visit Creation V2] Closing modal')

    // Hide modal
    this.modalTarget.classList.remove('modal-open')

    // Reset form
    this.formTarget.reset()

    // Remove marker
    this.removeMarker()

    // Exit adjust location mode if active
    if (this.adjustingLocation) {
      this.exitAdjustLocationMode()
    }

    // Clean up map click listener
    if (this.mapController && this.mapClickHandler) {
      this.mapController.map.off('click', this.mapClickHandler)
      this.mapClickHandler = null
    }
  }

  /**
   * Handle form submission
   */
  async submit(event) {
    event.preventDefault()

    console.log('[Visit Creation V2] Submitting form')

    // Disable submit button and show spinner
    this.submitButtonTarget.disabled = true
    this.submitSpinnerTarget.classList.remove('hidden')
    this.submitTextTarget.textContent = 'Creating...'

    const formData = new FormData(this.formTarget)

    const visitData = {
      visit: {
        name: formData.get('name'),
        started_at: formData.get('started_at'),
        ended_at: formData.get('ended_at'),
        latitude: parseFloat(formData.get('latitude')),
        longitude: parseFloat(formData.get('longitude')),
        status: 'confirmed'
      }
    }

    try {
      const response = await fetch('/api/v1/visits', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKeyValue}`,
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''
        },
        body: JSON.stringify(visitData)
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to create visit')
      }

      const createdVisit = await response.json()

      console.log('[Visit Creation V2] Visit created successfully', createdVisit)

      // Show success message
      this.showToast('Visit created successfully', 'success')

      // Close modal
      this.close()

      // Dispatch event to notify map controller
      document.dispatchEvent(new CustomEvent('visit:created', {
        detail: createdVisit
      }))
    } catch (error) {
      console.error('[Visit Creation V2] Error creating visit:', error)
      this.showToast(error.message || 'Failed to create visit', 'error')

      // Re-enable submit button
      this.submitButtonTarget.disabled = false
      this.submitSpinnerTarget.classList.add('hidden')
      this.submitTextTarget.textContent = 'Create Visit'
    }
  }

  /**
   * Enter adjust location mode
   */
  adjustLocation() {
    console.log('[Visit Creation V2] Entering adjust location mode')

    if (!this.mapController) return

    this.adjustingLocation = true

    // Change cursor to crosshair
    this.mapController.map.getCanvas().style.cursor = 'crosshair'

    // Show info message
    this.showToast('Click on the map to adjust visit location', 'info')

    // Add map click listener
    this.mapClickHandler = (e) => {
      const { lng, lat } = e.lngLat
      this.updateLocation(lat, lng)
    }

    this.mapController.map.once('click', this.mapClickHandler)
  }

  /**
   * Exit adjust location mode
   */
  exitAdjustLocationMode() {
    if (!this.mapController) return

    this.adjustingLocation = false
    this.mapController.map.getCanvas().style.cursor = ''
  }

  /**
   * Update location coordinates
   */
  updateLocation(lat, lng) {
    console.log('[Visit Creation V2] Updating location', { lat, lng })

    this.latitudeInputTarget.value = lat
    this.longitudeInputTarget.value = lng

    // Update location display
    this.updateLocationDisplay()

    // Update marker position
    if (this.marker) {
      this.marker.setLngLat([lng, lat])
    } else {
      this.addMarker(lat, lng)
    }

    // Exit adjust location mode
    this.exitAdjustLocationMode()
  }

  /**
   * Update location display text
   */
  updateLocationDisplay() {
    const lat = parseFloat(this.latitudeInputTarget.value)
    const lng = parseFloat(this.longitudeInputTarget.value)

    this.locationDisplayTarget.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`
  }

  /**
   * Add marker to map
   */
  addMarker(lat, lng) {
    if (!this.mapController) return

    // Remove existing marker if any
    this.removeMarker()

    // Create marker element
    const el = document.createElement('div')
    el.className = 'visit-creation-marker'
    el.innerHTML = '📍'
    el.style.fontSize = '30px'
    el.style.cursor = 'pointer'

    // Use maplibregl if available (from mapController)
    const maplibregl = window.maplibregl
    if (maplibregl) {
      this.marker = new maplibregl.Marker({ element: el, draggable: true })
        .setLngLat([lng, lat])
        .addTo(this.mapController.map)

      // Update coordinates on drag
      this.marker.on('dragend', () => {
        const lngLat = this.marker.getLngLat()
        this.updateLocation(lngLat.lat, lngLat.lng)
      })
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

    if (this.mapController && this.mapClickHandler) {
      this.mapController.map.off('click', this.mapClickHandler)
      this.mapClickHandler = null
    }
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
  showToast(message, type = 'info') {
    Toast[type](message)
  }
}
