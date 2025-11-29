import { Controller } from '@hotwired/stimulus'
import { Toast } from 'maps_v2/components/toast'

/**
 * Area creation controller for Maps V2
 * Handles area creation workflow with area drawer
 */
export default class extends Controller {
  static targets = [
    'modal',
    'form',
    'nameInput',
    'latitudeInput',
    'longitudeInput',
    'radiusInput',
    'radiusDisplay',
    'locationDisplay',
    'submitButton',
    'submitSpinner',
    'submitText'
  ]

  static values = {
    apiKey: String
  }

  static outlets = ['area-drawer']

  connect() {
    console.log('[Area Creation V2] Connected')
    this.latitude = null
    this.longitude = null
    this.radius = null
    this.mapsController = null
  }

  /**
   * Open modal and start drawing mode
   * @param {number} lat - Initial latitude (optional)
   * @param {number} lng - Initial longitude (optional)
   * @param {object} mapsController - Maps V2 controller reference
   */
  open(lat = null, lng = null, mapsController = null) {
    console.log('[Area Creation V2] Opening modal', { lat, lng })

    this.mapsController = mapsController
    this.latitude = lat
    this.longitude = lng
    this.radius = 100 // Default radius in meters

    // Update hidden inputs if coordinates provided
    if (lat && lng) {
      this.latitudeInputTarget.value = lat
      this.longitudeInputTarget.value = lng
      this.radiusInputTarget.value = this.radius
      this.updateLocationDisplay(lat, lng)
      this.updateRadiusDisplay(this.radius)
    }

    // Clear form
    this.nameInputTarget.value = ''

    // Show modal
    this.modalTarget.classList.add('modal-open')

    // Start drawing mode if area-drawer outlet is available
    if (this.hasAreaDrawerOutlet) {
      console.log('[Area Creation V2] Starting drawing mode')
      this.areaDrawerOutlet.startDrawing()
    } else {
      console.warn('[Area Creation V2] Area drawer outlet not found')
    }
  }

  /**
   * Close modal and cancel drawing
   */
  close() {
    console.log('[Area Creation V2] Closing modal')

    this.modalTarget.classList.remove('modal-open')

    // Cancel drawing mode
    if (this.hasAreaDrawerOutlet) {
      this.areaDrawerOutlet.cancelDrawing()
    }

    // Reset form
    this.formTarget.reset()
    this.latitude = null
    this.longitude = null
    this.radius = null
  }

  /**
   * Handle area drawn event from area-drawer
   */
  handleAreaDrawn(event) {
    console.log('[Area Creation V2] Area drawn', event.detail)

    const { area } = event.detail
    const [lng, lat] = area.center
    const radius = Math.round(area.radius)

    this.latitude = lat
    this.longitude = lng
    this.radius = radius

    // Update form fields
    this.latitudeInputTarget.value = lat
    this.longitudeInputTarget.value = lng
    this.radiusInputTarget.value = radius

    // Update displays
    this.updateLocationDisplay(lat, lng)
    this.updateRadiusDisplay(radius)

    console.log('[Area Creation V2] Form updated with drawn area')
  }

  /**
   * Update location display
   */
  updateLocationDisplay(lat, lng) {
    this.locationDisplayTarget.value = `${lat.toFixed(6)}, ${lng.toFixed(6)}`
  }

  /**
   * Update radius display
   */
  updateRadiusDisplay(radius) {
    this.radiusDisplayTarget.value = `${radius.toLocaleString()}`
  }

  /**
   * Handle form submission
   */
  async submit(event) {
    event.preventDefault()

    console.log('[Area Creation V2] Submitting form')

    // Validate
    if (!this.latitude || !this.longitude || !this.radius) {
      Toast.error('Please draw an area on the map first')
      return
    }

    const formData = new FormData(this.formTarget)
    const name = formData.get('name')

    if (!name || name.trim() === '') {
      Toast.error('Please enter an area name')
      this.nameInputTarget.focus()
      return
    }

    // Show loading state
    this.submitButtonTarget.disabled = true
    this.submitSpinnerTarget.classList.remove('hidden')
    this.submitTextTarget.textContent = 'Creating...'

    try {
      const response = await fetch('/api/v1/areas', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKeyValue}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name: name.trim(),
          latitude: this.latitude,
          longitude: this.longitude,
          radius: this.radius
        })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.message || 'Failed to create area')
      }

      const data = await response.json()
      console.log('[Area Creation V2] Area created:', data)

      Toast.success(`Area "${name}" created successfully`)

      // Dispatch event to notify maps controller
      document.dispatchEvent(new CustomEvent('area:created', {
        detail: { area: data }
      }))

      this.close()
    } catch (error) {
      console.error('[Area Creation V2] Failed to create area:', error)
      Toast.error(error.message || 'Failed to create area')
    } finally {
      // Reset button state
      this.submitButtonTarget.disabled = false
      this.submitSpinnerTarget.classList.add('hidden')
      this.submitTextTarget.textContent = 'Create Area'
    }
  }
}
