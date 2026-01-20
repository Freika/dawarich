/**
 * Search Manager
 * Manages location search functionality for Maps V2
 */

import { LocationSearchService } from '../services/location_search_service.js'

export class SearchManager {
  constructor(map, apiKey, timezone = 'UTC') {
    this.map = map
    this.service = new LocationSearchService(apiKey)
    this.searchInput = null
    this.resultsContainer = null
    this.debounceTimer = null
    this.debounceDelay = 300 // ms
    this.currentMarker = null
    this.currentVisitsData = null // Store visits data for click handling
    this.timezone = timezone
  }

  /**
   * Initialize search manager with DOM elements
   * @param {HTMLInputElement} searchInput - Search input element
   * @param {HTMLElement} resultsContainer - Container for search results
   */
  initialize(searchInput, resultsContainer) {
    this.searchInput = searchInput
    this.resultsContainer = resultsContainer

    if (!this.searchInput || !this.resultsContainer) {
      console.warn('SearchManager: Missing required DOM elements')
      return
    }

    this.attachEventListeners()
  }

  /**
   * Attach event listeners to search input
   */
  attachEventListeners() {
    // Input event with debouncing
    this.searchInput.addEventListener('input', (e) => {
      this.handleSearchInput(e.target.value)
    })

    // Prevent results from hiding when clicking inside results container
    this.resultsContainer.addEventListener('mousedown', (e) => {
      e.preventDefault() // Prevent blur event on search input
    })

    // Clear results when clicking outside
    document.addEventListener('click', (e) => {
      if (!this.searchInput.contains(e.target) && !this.resultsContainer.contains(e.target)) {
        // Delay to allow animations to complete
        setTimeout(() => {
          this.clearResults()
        }, 100)
      }
    })

    // Handle Enter key
    this.searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault()
        const firstResult = this.resultsContainer.querySelector('.search-result-item')
        if (firstResult) {
          firstResult.click()
        }
      }
    })
  }

  /**
   * Handle search input with debouncing
   * @param {string} query - Search query
   */
  handleSearchInput(query) {
    clearTimeout(this.debounceTimer)

    if (!query || query.length < 2) {
      this.clearResults()
      return
    }

    this.debounceTimer = setTimeout(async () => {
      try {
        this.showLoading()
        const suggestions = await this.service.fetchSuggestions(query)
        this.displayResults(suggestions)
      } catch (error) {
        this.showError('Failed to fetch suggestions')
        console.error('SearchManager: Search error:', error)
      }
    }, this.debounceDelay)
  }

  /**
   * Display search results
   * @param {Array} suggestions - Array of location suggestions
   */
  displayResults(suggestions) {
    this.clearResults()

    if (!suggestions || suggestions.length === 0) {
      this.showNoResults()
      return
    }

    suggestions.forEach(suggestion => {
      const resultItem = this.createResultItem(suggestion)
      this.resultsContainer.appendChild(resultItem)
    })

    this.resultsContainer.classList.remove('hidden')
  }

  /**
   * Create a result item element
   * @param {Object} suggestion - Location suggestion
   * @returns {HTMLElement} Result item element
   */
  createResultItem(suggestion) {
    const item = document.createElement('div')
    item.className = 'search-result-item p-3 hover:bg-base-200 cursor-pointer rounded-lg transition-colors'
    item.setAttribute('data-lat', suggestion.lat)
    item.setAttribute('data-lon', suggestion.lon)

    const name = document.createElement('div')
    name.className = 'font-medium text-sm'
    name.textContent = suggestion.name || 'Unknown location'

    if (suggestion.address) {
      const address = document.createElement('div')
      address.className = 'text-xs text-base-content/60 mt-1'
      address.textContent = suggestion.address
      item.appendChild(name)
      item.appendChild(address)
    } else {
      item.appendChild(name)
    }

    item.addEventListener('click', () => {
      this.handleResultClick(suggestion)
    })

    return item
  }

  /**
   * Handle click on search result
   * @param {Object} location - Selected location
   */
  async handleResultClick(location) {
    // Fly to location on map
    this.map.flyTo({
      center: [location.lon, location.lat],
      zoom: 15,
      duration: 1000
    })

    // Add temporary marker
    this.addSearchMarker(location.lon, location.lat)

    // Update search input
    if (this.searchInput) {
      this.searchInput.value = location.name || ''
    }

    // Show loading state in results
    this.showVisitsLoading(location.name)

    // Search for visits at this location
    try {
      const visitsData = await this.service.searchVisits({
        lat: location.lat,
        lon: location.lon,
        name: location.name,
        address: location.address || ''
      })

      // Display visits results
      this.displayVisitsResults(visitsData, location)
    } catch (error) {
      console.error('SearchManager: Failed to fetch visits:', error)
      this.showError('Failed to load visits for this location')
    }

    // Dispatch custom event for other components
    this.dispatchSearchEvent(location)
  }

  /**
   * Add a temporary marker at search location
   * @param {number} lon - Longitude
   * @param {number} lat - Latitude
   */
  addSearchMarker(lon, lat) {
    // Remove existing marker
    if (this.currentMarker) {
      this.currentMarker.remove()
    }

    // Create marker element
    const el = document.createElement('div')
    el.className = 'search-marker'
    el.style.cssText = `
      width: 30px;
      height: 30px;
      background-color: #3b82f6;
      border: 3px solid white;
      border-radius: 50%;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      cursor: pointer;
    `

    // Add marker to map (MapLibre GL style)
    if (this.map.getSource) {
      // Use MapLibre marker
      const maplibregl = window.maplibregl
      if (maplibregl) {
        this.currentMarker = new maplibregl.Marker({ element: el })
          .setLngLat([lon, lat])
          .addTo(this.map)
      }
    }
  }

  /**
   * Dispatch custom search event
   * @param {Object} location - Selected location
   */
  dispatchSearchEvent(location) {
    const event = new CustomEvent('location-search:selected', {
      detail: { location },
      bubbles: true
    })
    document.dispatchEvent(event)
  }

  /**
   * Show loading indicator
   */
  showLoading() {
    this.clearResults()
    this.resultsContainer.innerHTML = `
      <div class="p-3 text-sm text-base-content/60 flex items-center gap-2">
        <span class="loading loading-spinner loading-sm"></span>
        Searching...
      </div>
    `
    this.resultsContainer.classList.remove('hidden')
  }

  /**
   * Show no results message
   */
  showNoResults() {
    this.resultsContainer.innerHTML = `
      <div class="p-3 text-sm text-base-content/60">
        No locations found
      </div>
    `
    this.resultsContainer.classList.remove('hidden')
  }

  /**
   * Show error message
   * @param {string} message - Error message
   */
  showError(message) {
    this.resultsContainer.innerHTML = `
      <div class="p-3 text-sm text-error">
        ${message}
      </div>
    `
    this.resultsContainer.classList.remove('hidden')
  }

  /**
   * Show loading state while fetching visits
   * @param {string} locationName - Name of the location being searched
   */
  showVisitsLoading(locationName) {
    this.resultsContainer.innerHTML = `
      <div class="p-4 text-sm text-base-content/60">
        <div class="flex items-center gap-2 mb-2">
          <span class="loading loading-spinner loading-sm"></span>
          <span class="font-medium">Searching for visits...</span>
        </div>
        <div class="text-xs">${this.escapeHtml(locationName)}</div>
      </div>
    `
    this.resultsContainer.classList.remove('hidden')
  }

  /**
   * Display visits results
   * @param {Object} visitsData - Visits data from API
   * @param {Object} location - Selected location
   */
  displayVisitsResults(visitsData, location) {
    // Store visits data for click handling
    this.currentVisitsData = visitsData

    if (!visitsData.locations || visitsData.locations.length === 0) {
      this.resultsContainer.innerHTML = `
        <div class="p-6 text-center text-base-content/60">
          <div class="text-3xl mb-3">📍</div>
          <div class="text-sm font-medium">No visits found</div>
          <div class="text-xs mt-1">No visits found for "${this.escapeHtml(location.name)}"</div>
        </div>
      `
      this.resultsContainer.classList.remove('hidden')
      return
    }

    // Display visits grouped by location
    let html = `
      <div class="p-4 border-b bg-base-200">
        <div class="text-sm font-medium">Found ${visitsData.total_locations} location(s)</div>
        <div class="text-xs text-base-content/60 mt-1">for "${this.escapeHtml(location.name)}"</div>
      </div>
    `

    visitsData.locations.forEach((loc, index) => {
      html += this.buildLocationVisitsHtml(loc, index)
    })

    this.resultsContainer.innerHTML = html
    this.resultsContainer.classList.remove('hidden')

    // Attach event listeners to year toggles and visit items
    this.attachYearToggleListeners()
  }

  /**
   * Build HTML for a location with its visits
   * @param {Object} location - Location with visits
   * @param {number} index - Location index
   * @returns {string} HTML string
   */
  buildLocationVisitsHtml(location, index) {
    const visits = location.visits || []
    if (visits.length === 0) return ''

    // Handle case where visits are sorted newest first
    const sortedVisits = [...visits].sort((a, b) => new Date(a.date) - new Date(b.date))
    const firstVisit = sortedVisits[0]
    const lastVisit = sortedVisits[sortedVisits.length - 1]
    const visitsByYear = this.groupVisitsByYear(visits)

    // Use place_name, address, or coordinates as fallback
    const displayName = location.place_name || location.address ||
                       `Location (${location.coordinates?.[0]?.toFixed(4)}, ${location.coordinates?.[1]?.toFixed(4)})`

    return `
      <div class="location-result border-b" data-location-index="${index}">
        <div class="p-4">
          <div class="font-medium text-sm">${this.escapeHtml(displayName)}</div>
          ${location.address && location.place_name !== location.address ?
            `<div class="text-xs text-base-content/60 mt-1">${this.escapeHtml(location.address)}</div>` : ''}
          <div class="flex justify-between items-center mt-3">
            <div class="text-xs text-primary">${location.total_visits} visit(s)</div>
            <div class="text-xs text-base-content/60">
              first ${this.formatDateShort(firstVisit.date)}, last ${this.formatDateShort(lastVisit.date)}
            </div>
          </div>
        </div>

        <!-- Years Section -->
        <div class="border-t bg-base-200">
          ${Object.entries(visitsByYear).map(([year, yearVisits]) => `
            <div class="year-section">
              <div class="year-toggle p-3 hover:bg-base-300 cursor-pointer border-b flex justify-between items-center"
                   data-location-index="${index}" data-year="${year}">
                <span class="text-sm font-medium">${year}</span>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-primary">${yearVisits.length} visits</span>
                  <span class="year-arrow text-base-content/40 transition-transform">▶</span>
                </div>
              </div>
              <div class="year-visits hidden" id="year-${index}-${year}">
                ${yearVisits.map((visit) => `
                  <div class="visit-item text-xs py-2 px-4 border-b hover:bg-base-300 cursor-pointer"
                       data-location-index="${index}" data-visit-index="${visits.indexOf(visit)}">
                    <div class="flex justify-between items-start">
                      <div>📍 ${this.formatDateTime(visit.date)}</div>
                      <div class="text-xs text-base-content/60">${visit.duration_estimate || 'N/A'}</div>
                    </div>
                  </div>
                `).join('')}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `
  }

  /**
   * Group visits by year
   * @param {Array} visits - Array of visits
   * @returns {Object} Visits grouped by year
   */
  groupVisitsByYear(visits) {
    const groups = {}
    visits.forEach(visit => {
      const year = new Date(visit.date).getFullYear().toString()
      if (!groups[year]) {
        groups[year] = []
      }
      groups[year].push(visit)
    })
    return groups
  }

  /**
   * Attach event listeners to year toggle elements
   */
  attachYearToggleListeners() {
    const toggles = this.resultsContainer.querySelectorAll('.year-toggle')
    toggles.forEach(toggle => {
      toggle.addEventListener('click', (e) => {
        const locationIndex = e.currentTarget.dataset.locationIndex
        const year = e.currentTarget.dataset.year
        const visitsContainer = document.getElementById(`year-${locationIndex}-${year}`)
        const arrow = e.currentTarget.querySelector('.year-arrow')

        if (visitsContainer) {
          visitsContainer.classList.toggle('hidden')
          arrow.style.transform = visitsContainer.classList.contains('hidden') ? 'rotate(0deg)' : 'rotate(90deg)'
        }
      })
    })

    // Attach event listeners to individual visit items
    const visitItems = this.resultsContainer.querySelectorAll('.visit-item')
    visitItems.forEach(item => {
      item.addEventListener('click', (e) => {
        e.stopPropagation()
        const locationIndex = parseInt(item.dataset.locationIndex)
        const visitIndex = parseInt(item.dataset.visitIndex)
        this.handleVisitClick(locationIndex, visitIndex)
      })
    })
  }

  /**
   * Handle click on individual visit item
   * @param {number} locationIndex - Index of location in results
   * @param {number} visitIndex - Index of visit within location
   */
  handleVisitClick(locationIndex, visitIndex) {
    if (!this.currentVisitsData || !this.currentVisitsData.locations) return

    const location = this.currentVisitsData.locations[locationIndex]
    if (!location || !location.visits) return

    const visit = location.visits[visitIndex]
    if (!visit) return

    // Fly to visit coordinates (more precise than location coordinates)
    const [lat, lon] = visit.coordinates || location.coordinates
    this.map.flyTo({
      center: [lon, lat],
      zoom: 18,
      duration: 1000
    })

    // Extract visit details
    const visitDetails = visit.visit_details || {}
    const startTime = visitDetails.start_time || visit.date
    const endTime = visitDetails.end_time || visit.date
    const placeName = location.place_name || location.address || 'Unnamed Location'

    // Open create visit modal
    this.openCreateVisitModal({
      name: placeName,
      latitude: lat,
      longitude: lon,
      started_at: startTime,
      ended_at: endTime
    })
  }

  /**
   * Open modal to create a visit with prefilled data
   * @param {Object} visitData - Visit data to prefill
   */
  openCreateVisitModal(visitData) {
    // Create modal HTML
    const modalId = 'create-visit-modal'

    // Remove existing modal if present
    const existingModal = document.getElementById(modalId)
    if (existingModal) {
      existingModal.remove()
    }

    const modal = document.createElement('div')
    modal.id = modalId
    modal.innerHTML = `
      <input type="checkbox" id="${modalId}-toggle" class="modal-toggle" checked />
      <div class="modal" role="dialog">
        <div class="modal-box">
          <h3 class="text-lg font-bold mb-4">Create Visit</h3>

          <form id="${modalId}-form">
            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">Name</span>
              </label>
              <input type="text" name="name" class="input input-bordered w-full"
                     value="${this.escapeHtml(visitData.name)}" required />
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">Start Time</span>
              </label>
              <input type="datetime-local" name="started_at" class="input input-bordered w-full"
                     value="${this.formatDateTimeForInput(visitData.started_at)}" required />
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">End Time</span>
              </label>
              <input type="datetime-local" name="ended_at" class="input input-bordered w-full"
                     value="${this.formatDateTimeForInput(visitData.ended_at)}" required />
            </div>

            <input type="hidden" name="latitude" value="${visitData.latitude}" />
            <input type="hidden" name="longitude" value="${visitData.longitude}" />

            <div class="modal-action">
              <button type="button" class="btn" data-action="close">Cancel</button>
              <button type="submit" class="btn btn-primary">
                <span class="submit-text">Create Visit</span>
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
    const form = modal.querySelector('form')
    const closeBtn = modal.querySelector('[data-action="close"]')
    const modalToggle = modal.querySelector(`#${modalId}-toggle`)
    const backdrop = modal.querySelector('.modal-backdrop')

    form.addEventListener('submit', (e) => {
      e.preventDefault()
      this.submitCreateVisit(form, modal)
    })

    closeBtn.addEventListener('click', () => {
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)
    })

    backdrop.addEventListener('click', () => {
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)
    })
  }

  /**
   * Submit create visit form
   * @param {HTMLFormElement} form - Form element
   * @param {HTMLElement} modal - Modal element
   */
  async submitCreateVisit(form, modal) {
    const submitBtn = form.querySelector('button[type="submit"]')
    const submitText = submitBtn.querySelector('.submit-text')
    const spinner = submitBtn.querySelector('.loading')

    // Disable submit button and show loading
    submitBtn.disabled = true
    submitText.classList.add('hidden')
    spinner.classList.remove('hidden')

    try {
      const formData = new FormData(form)
      const visitData = {
        name: formData.get('name'),
        latitude: parseFloat(formData.get('latitude')),
        longitude: parseFloat(formData.get('longitude')),
        started_at: formData.get('started_at'),
        ended_at: formData.get('ended_at'),
        status: 'confirmed'
      }

      const response = await this.service.createVisit(visitData)

      if (response.error) {
        throw new Error(response.error)
      }

      // Success - close modal and show success message
      const modalToggle = modal.querySelector('.modal-toggle')
      modalToggle.checked = false
      setTimeout(() => modal.remove(), 300)

      // Show success notification
      this.showSuccessNotification('Visit created successfully!')

      // Dispatch custom event for other components to react
      document.dispatchEvent(new CustomEvent('visit:created', {
        detail: { visit: response, coordinates: [visitData.longitude, visitData.latitude] }
      }))

    } catch (error) {
      console.error('Failed to create visit:', error)
      alert(`Failed to create visit: ${error.message}`)

      // Re-enable submit button
      submitBtn.disabled = false
      submitText.classList.remove('hidden')
      spinner.classList.add('hidden')
    }
  }

  /**
   * Show success notification
   * @param {string} message - Success message
   */
  showSuccessNotification(message) {
    const notification = document.createElement('div')
    notification.className = 'toast toast-top toast-end z-[9999]'
    notification.innerHTML = `
      <div class="alert alert-success">
        <span>✓ ${this.escapeHtml(message)}</span>
      </div>
    `
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  /**
   * Format datetime for input field (YYYY-MM-DDTHH:MM)
   * @param {string} dateString - Date string
   * @returns {string} Formatted datetime
   */
  formatDateTimeForInput(dateString) {
    const date = new Date(dateString)
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    const hours = String(date.getHours()).padStart(2, '0')
    const minutes = String(date.getMinutes()).padStart(2, '0')
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  /**
   * Format date in short format
   * @param {string} dateString - Date string
   * @returns {string} Formatted date
   */
  formatDateShort(dateString) {
    const date = new Date(dateString)
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: this.timezone })
  }

  /**
   * Format date and time
   * @param {string} dateString - Date string
   * @returns {string} Formatted date and time
   */
  formatDateTime(dateString) {
    const date = new Date(dateString)
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      timeZone: this.timezone
    })
  }

  /**
   * Escape HTML to prevent XSS
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  escapeHtml(str) {
    if (!str) return ''
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }

  /**
   * Clear search results
   */
  clearResults() {
    if (this.resultsContainer) {
      this.resultsContainer.innerHTML = ''
      this.resultsContainer.classList.add('hidden')
    }
  }

  /**
   * Clear search marker
   */
  clearMarker() {
    if (this.currentMarker) {
      this.currentMarker.remove()
      this.currentMarker = null
    }
  }

  /**
   * Cleanup
   */
  destroy() {
    clearTimeout(this.debounceTimer)
    this.clearMarker()
    this.clearResults()
  }
}
