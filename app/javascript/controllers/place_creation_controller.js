import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "nameInput", "latitudeInput", "longitudeInput",
                   "nearbyList", "loadingSpinner", "tagCheckboxes", "loadMoreContainer", "loadMoreButton"]
  static values = {
    apiKey: String
  }

  connect() {
    this.setupEventListeners()
    this.currentRadius = 0.5 // Start with 500m (0.5km)
    this.maxRadius = 1.5 // Max 1500m (1.5km)
    this.setupTagListeners()
  }

  setupEventListeners() {
    document.addEventListener('place:create', (e) => {
      this.open(e.detail.latitude, e.detail.longitude)
    })
  }

  setupTagListeners() {
    // Listen for checkbox changes to update badge styling
    if (this.hasTagCheckboxesTarget) {
      this.tagCheckboxesTarget.addEventListener('change', (e) => {
        if (e.target.type === 'checkbox' && e.target.name === 'tag_ids[]') {
          const badge = e.target.nextElementSibling
          const color = badge.dataset.color

          if (e.target.checked) {
            // Filled style
            badge.classList.remove('badge-outline')
            badge.style.backgroundColor = color
            badge.style.borderColor = color
            badge.style.color = 'white'
          } else {
            // Outline style
            badge.classList.add('badge-outline')
            badge.style.backgroundColor = 'transparent'
            badge.style.borderColor = color
            badge.style.color = color
          }
        }
      })
    }
  }

  async open(latitude, longitude) {
    this.latitudeInputTarget.value = latitude
    this.longitudeInputTarget.value = longitude
    this.currentRadius = 0.5 // Reset radius when opening modal

    this.modalTarget.classList.add('modal-open')
    this.nameInputTarget.focus()

    await this.loadNearbyPlaces(latitude, longitude)
  }

  close() {
    this.modalTarget.classList.remove('modal-open')
    this.formTarget.reset()
    this.nearbyListTarget.innerHTML = ''
    this.loadMoreContainerTarget.classList.add('hidden')
    this.currentRadius = 0.5

    const event = new CustomEvent('place:create:cancelled')
    document.dispatchEvent(event)
  }

  async loadNearbyPlaces(latitude, longitude, radius = null) {
    this.loadingSpinnerTarget.classList.remove('hidden')

    // Use provided radius or current radius
    const searchRadius = radius || this.currentRadius
    const isLoadingMore = radius !== null && radius > this.currentRadius - 0.5

    // Only clear the list on initial load, not when loading more
    if (!isLoadingMore) {
      this.nearbyListTarget.innerHTML = ''
    }

    try {
      const response = await fetch(
        `/api/v1/places/nearby?latitude=${latitude}&longitude=${longitude}&radius=${searchRadius}&limit=5`,
        { headers: { 'Authorization': `Bearer ${this.apiKeyValue}` } }
      )

      if (!response.ok) throw new Error('Failed to load nearby places')

      const data = await response.json()
      this.renderNearbyPlaces(data.places, isLoadingMore)

      // Show load more button if we can expand radius further
      if (searchRadius < this.maxRadius) {
        this.loadMoreContainerTarget.classList.remove('hidden')
        this.updateLoadMoreButton(searchRadius)
      } else {
        this.loadMoreContainerTarget.classList.add('hidden')
      }
    } catch (error) {
      console.error('Error loading nearby places:', error)
      this.nearbyListTarget.innerHTML = '<p class="text-error">Failed to load suggestions</p>'
    } finally {
      this.loadingSpinnerTarget.classList.add('hidden')
    }
  }

  renderNearbyPlaces(places, append = false) {
    if (!places || places.length === 0) {
      if (!append) {
        this.nearbyListTarget.innerHTML = '<p class="text-sm text-gray-500">No nearby places found</p>'
      }
      return
    }

    // Calculate starting index based on existing items
    const currentCount = append ? this.nearbyListTarget.querySelectorAll('.card').length : 0

    const html = places.map((place, index) => `
      <div class="card card-compact bg-base-200 cursor-pointer hover:bg-base-300 transition"
           data-action="click->place-creation#selectNearby"
           data-place-name="${this.escapeHtml(place.name)}"
           data-place-latitude="${place.latitude}"
           data-place-longitude="${place.longitude}">
        <div class="card-body">
          <div class="flex gap-2">
            <span class="badge badge-primary badge-sm">#${currentCount + index + 1}</span>
            <div class="flex-1">
              <h4 class="font-semibold">${this.escapeHtml(place.name)}</h4>
              ${place.street ? `<p class="text-sm">${this.escapeHtml(place.street)}</p>` : ''}
              ${place.city ? `<p class="text-xs text-gray-500">${this.escapeHtml(place.city)}, ${this.escapeHtml(place.country || '')}</p>` : ''}
            </div>
          </div>
        </div>
      </div>
    `).join('')

    if (append) {
      this.nearbyListTarget.insertAdjacentHTML('beforeend', html)
    } else {
      this.nearbyListTarget.innerHTML = html
    }
  }

  async loadMore() {
    // Increase radius by 500m (0.5km) up to max of 1500m (1.5km)
    if (this.currentRadius >= this.maxRadius) return

    this.currentRadius = Math.min(this.currentRadius + 0.5, this.maxRadius)

    const latitude = parseFloat(this.latitudeInputTarget.value)
    const longitude = parseFloat(this.longitudeInputTarget.value)

    await this.loadNearbyPlaces(latitude, longitude, this.currentRadius)
  }

  updateLoadMoreButton(currentRadius) {
    const nextRadius = Math.min(currentRadius + 0.5, this.maxRadius)
    const radiusInMeters = Math.round(nextRadius * 1000)
    this.loadMoreButtonTarget.textContent = `Load More (search up to ${radiusInMeters}m)`
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
