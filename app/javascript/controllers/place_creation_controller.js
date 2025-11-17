import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "nameInput", "latitudeInput", "longitudeInput", 
                   "nearbyList", "loadingSpinner", "tagCheckboxes"]
  static values = {
    apiKey: String
  }

  connect() {
    this.setupEventListeners()
  }

  setupEventListeners() {
    document.addEventListener('place:create', (e) => {
      this.open(e.detail.latitude, e.detail.longitude)
    })
  }

  async open(latitude, longitude) {
    this.latitudeInputTarget.value = latitude
    this.longitudeInputTarget.value = longitude
    
    this.modalTarget.classList.add('modal-open')
    this.nameInputTarget.focus()
    
    await this.loadNearbyPlaces(latitude, longitude)
  }

  close() {
    this.modalTarget.classList.remove('modal-open')
    this.formTarget.reset()
    this.nearbyListTarget.innerHTML = ''
    
    const event = new CustomEvent('place:create:cancelled')
    document.dispatchEvent(event)
  }

  async loadNearbyPlaces(latitude, longitude) {
    this.loadingSpinnerTarget.classList.remove('hidden')
    this.nearbyListTarget.innerHTML = ''

    try {
      const response = await fetch(
        `/api/v1/places/nearby?latitude=${latitude}&longitude=${longitude}&limit=5`,
        { headers: { 'Authorization': `Bearer ${this.apiKeyValue}` } }
      )

      if (!response.ok) throw new Error('Failed to load nearby places')

      const data = await response.json()
      this.renderNearbyPlaces(data.places)
    } catch (error) {
      console.error('Error loading nearby places:', error)
      this.nearbyListTarget.innerHTML = '<p class="text-error">Failed to load suggestions</p>'
    } finally {
      this.loadingSpinnerTarget.classList.add('hidden')
    }
  }

  renderNearbyPlaces(places) {
    if (!places || places.length === 0) {
      this.nearbyListTarget.innerHTML = '<p class="text-sm text-gray-500">No nearby places found</p>'
      return
    }

    const html = places.map(place => `
      <div class="card card-compact bg-base-200 cursor-pointer hover:bg-base-300 transition"
           data-action="click->place-creation#selectNearby"
           data-place-name="${this.escapeHtml(place.name)}"
           data-place-latitude="${place.latitude}"
           data-place-longitude="${place.longitude}">
        <div class="card-body">
          <h4 class="font-semibold">${this.escapeHtml(place.name)}</h4>
          ${place.street ? `<p class="text-sm">${this.escapeHtml(place.street)}</p>` : ''}
          ${place.city ? `<p class="text-xs text-gray-500">${this.escapeHtml(place.city)}, ${this.escapeHtml(place.country || '')}</p>` : ''}
        </div>
      </div>
    `).join('')

    this.nearbyListTarget.innerHTML = html
  }

  selectNearby(event) {
    const element = event.currentTarget
    this.nameInputTarget.value = element.dataset.placeName
    this.latitudeInputTarget.value = element.dataset.placeLatitude
    this.longitudeInputTarget.value = element.dataset.placeLongitude
  }

  async submit(event) {
    event.preventDefault()

    const formData = new FormData(this.formTarget)
    const tagIds = Array.from(this.formTarget.querySelectorAll('input[name="tag_ids[]"]:checked'))
                        .map(cb => cb.value)

    const payload = {
      place: {
        name: formData.get('name'),
        latitude: parseFloat(formData.get('latitude')),
        longitude: parseFloat(formData.get('longitude')),
        source: 'manual',
        tag_ids: tagIds
      }
    }

    try {
      const response = await fetch('/api/v1/places', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKeyValue}`
        },
        body: JSON.stringify(payload)
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.errors?.join(', ') || 'Failed to create place')
      }

      const place = await response.json()
      
      this.close()
      this.showNotification('Place created successfully!', 'success')
      
      const event = new CustomEvent('place:created', { detail: { place } })
      document.dispatchEvent(event)
    } catch (error) {
      console.error('Error creating place:', error)
      this.showNotification(error.message, 'error')
    }
  }

  showNotification(message, type = 'info') {
    const event = new CustomEvent('notification:show', {
      detail: { message, type },
      bubbles: true
    })
    document.dispatchEvent(event)
  }

  escapeHtml(text) {
    if (!text) return ''
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
