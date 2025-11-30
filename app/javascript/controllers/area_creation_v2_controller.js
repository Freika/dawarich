import { Controller } from '@hotwired/stimulus'

/**
 * Area creation controller
 * Handles the area creation modal and form submission
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

  connect() {
    this.area = null
    this.setupEventListeners()
    console.log('[Area Creation V2] Controller connected')
  }

  /**
   * Setup event listeners for area drawing
   */
  setupEventListeners() {
    document.addEventListener('area:drawn', (e) => {
      console.log('[Area Creation V2] area:drawn event received:', e.detail)
      this.open(e.detail.center, e.detail.radius)
    })
  }

  /**
   * Open the modal with area data
   */
  open(center, radius) {
    console.log('[Area Creation V2] open() called with center:', center, 'radius:', radius)

    // Store area data
    this.area = { center, radius }

    // Update form fields
    this.latitudeInputTarget.value = center[1]
    this.longitudeInputTarget.value = center[0]
    this.radiusInputTarget.value = Math.round(radius)
    this.radiusDisplayTarget.value = Math.round(radius)
    this.locationDisplayTarget.value = `${center[1].toFixed(6)}, ${center[0].toFixed(6)}`

    // Show modal
    this.modalTarget.classList.add('modal-open')
    this.nameInputTarget.focus()
  }

  /**
   * Close the modal
   */
  close() {
    this.modalTarget.classList.remove('modal-open')
    this.resetForm()
  }

  /**
   * Submit the form
   */
  async submit(event) {
    event.preventDefault()

    if (!this.area) {
      console.error('No area data available')
      return
    }

    const formData = new FormData(this.formTarget)
    const name = formData.get('name')
    const latitude = parseFloat(formData.get('latitude'))
    const longitude = parseFloat(formData.get('longitude'))
    const radius = parseFloat(formData.get('radius'))

    if (!name || !latitude || !longitude || !radius) {
      alert('Please fill in all required fields')
      return
    }

    this.setLoading(true)

    try {
      const response = await fetch('/api/v1/areas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKeyValue}`
        },
        body: JSON.stringify({
          name,
          latitude,
          longitude,
          radius
        })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.message || 'Failed to create area')
      }

      const area = await response.json()

      // Close modal
      this.close()

      // Dispatch document event for area created
      document.dispatchEvent(new CustomEvent('area:created', {
        detail: { area }
      }))

    } catch (error) {
      console.error('Error creating area:', error)
      alert(`Error creating area: ${error.message}`)
    } finally {
      this.setLoading(false)
    }
  }

  /**
   * Set loading state
   */
  setLoading(loading) {
    this.submitButtonTarget.disabled = loading

    if (loading) {
      this.submitSpinnerTarget.classList.remove('hidden')
      this.submitTextTarget.textContent = 'Creating...'
    } else {
      this.submitSpinnerTarget.classList.add('hidden')
      this.submitTextTarget.textContent = 'Create Area'
    }
  }

  /**
   * Reset form
   */
  resetForm() {
    this.formTarget.reset()
    this.area = null
    this.radiusDisplayTarget.value = ''
    this.locationDisplayTarget.value = ''
  }

  /**
   * Show success message
   */
  showSuccess(message) {
    // You can replace this with a toast notification if available
    console.log(message)

    // Try to use the Toast component if available
    if (window.Toast) {
      window.Toast.show(message, 'success')
    }
  }
}
