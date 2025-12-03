import { Controller } from '@hotwired/stimulus'
import { Toast } from 'maps_maplibre/components/toast'

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
    'longitudeInput'
  ]

  static values = {
    apiKey: String
  }

  connect() {
    console.log('[Visit Creation V2] Controller connected')
    this.marker = null
    this.mapController = null
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
  }

  /**
   * Handle form submission
   */
  async submit(event) {
    event.preventDefault()

    console.log('[Visit Creation V2] Submitting form')

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
    const el = document.createElement('div')
    el.className = 'visit-creation-marker'
    el.innerHTML = '📍'
    el.style.fontSize = '30px'

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
  showToast(message, type = 'info') {
    Toast[type](message)
  }
}
