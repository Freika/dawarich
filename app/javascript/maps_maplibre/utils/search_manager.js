/**
 * Search Manager
 * Manages location search functionality for Maps V2
 */

import { translate } from "i18n"
import { LocationSearchService } from "../services/location_search_service.js"
import { createVisitModal } from "./search/create_visit_modal"
import { visitsResults } from "./search/visits_results"

export class SearchManager {
  constructor(map, apiKey) {
    this.map = map
    this.service = new LocationSearchService(apiKey)
    this.searchInput = null
    this.resultsContainer = null
    this.debounceTimer = null
    this.debounceDelay = 300 // ms
    this.currentMarker = null
    this.currentVisitsData = null // Store visits data for click handling
    this._activeRenderId = 0
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
      console.warn("SearchManager: Missing required DOM elements")
      return
    }

    this.attachEventListeners()
  }

  /**
   * Attach event listeners to search input
   */
  attachEventListeners() {
    // Input event with debouncing
    this.searchInput.addEventListener("input", (e) => {
      this.handleSearchInput(e.target.value)
    })

    // Prevent results from hiding when clicking inside results container
    this.resultsContainer.addEventListener("mousedown", (e) => {
      e.preventDefault() // Prevent blur event on search input
    })

    // Clear results when clicking outside
    this._documentClickHandler = (e) => {
      const eventPath = e.composedPath()
      if (
        !eventPath.includes(this.searchInput) &&
        !eventPath.includes(this.resultsContainer)
      ) {
        // Delay to allow animations to complete
        setTimeout(() => {
          this.clearResults()
        }, 100)
      }
    }
    document.addEventListener("click", this._documentClickHandler)

    // Handle Enter key
    this.searchInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        const firstResult = this.resultsContainer.querySelector(
          ".search-result-item",
        )
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
      const renderId = ++this._activeRenderId
      try {
        this.showLoading()
        const suggestions = await this.service.fetchSuggestions(query)
        if (renderId !== this._activeRenderId) return
        this.displayResults(suggestions)
      } catch (error) {
        if (renderId !== this._activeRenderId) return
        this.showError(translate("search.suggestions_failed"))
        console.error("SearchManager: Search error:", error)
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

    suggestions.forEach((suggestion) => {
      const resultItem = this.createResultItem(suggestion)
      this.resultsContainer.appendChild(resultItem)
    })

    this.resultsContainer.classList.remove("hidden")
  }

  /**
   * Create a result item element
   * @param {Object} suggestion - Location suggestion
   * @returns {HTMLElement} Result item element
   */
  createResultItem(suggestion) {
    const item = document.createElement("div")
    item.className =
      "search-result-item p-3 hover:bg-base-200 cursor-pointer rounded-lg transition-colors"
    item.setAttribute("data-lat", suggestion.lat)
    item.setAttribute("data-lon", suggestion.lon)

    const name = document.createElement("div")
    name.className = "font-medium text-sm"
    name.textContent = suggestion.name || translate("search.unknown_location")

    if (suggestion.address) {
      const address = document.createElement("div")
      address.className = "text-xs text-base-content/60 mt-1"
      address.textContent = suggestion.address
      item.appendChild(name)
      item.appendChild(address)
    } else {
      item.appendChild(name)
    }

    item.addEventListener("click", () => {
      this.handleResultClick(suggestion)
    })

    return item
  }

  /**
   * Handle click on search result
   * @param {Object} location - Selected location
   */
  async handleResultClick(location) {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = null
    const renderId = ++this._activeRenderId

    // Fly to location on map
    this.map.flyTo({
      center: [location.lon, location.lat],
      zoom: 15,
      duration: 1000,
    })

    // Add temporary marker
    this.addSearchMarker(location.lon, location.lat)

    // Update search input
    if (this.searchInput) {
      this.searchInput.value = location.name || ""
    }

    // Show loading state in results
    this.showVisitsLoading(location.name)

    // Search for visits at this location
    try {
      const visitsData = await this.service.searchVisits({
        lat: location.lat,
        lon: location.lon,
        name: location.name,
        address: location.address || "",
      })

      if (renderId !== this._activeRenderId) return

      // Display visits results
      this.displayVisitsResults(visitsData, location)
    } catch (error) {
      if (renderId !== this._activeRenderId) return
      console.error("SearchManager: Failed to fetch visits:", error)
      this.showError(translate("search.visits_load_failed"))
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
    const el = document.createElement("div")
    el.className = "search-marker"
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
    const event = new CustomEvent("location-search:selected", {
      detail: { location },
      bubbles: true,
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
        ${translate("search.searching")}
      </div>
    `
    this.resultsContainer.classList.remove("hidden")
  }

  /**
   * Show no results message
   */
  showNoResults() {
    this.resultsContainer.innerHTML = `
      <div class="p-3 text-sm text-base-content/60">
        ${translate("search.no_locations")}
      </div>
    `
    this.resultsContainer.classList.remove("hidden")
  }

  /**
   * Show error message
   * @param {string} message - Error message
   */
  showError(message) {
    this.resultsContainer.innerHTML = `
      <div class="p-3 text-sm text-error">
        ${this.escapeHtml(message)}
      </div>
    `
    this.resultsContainer.classList.remove("hidden")
  }

  /**
   * Show loading state while fetching visits
   * @param {string} locationName - Name of the location being searched
   */
  /**
   * Escape HTML to prevent XSS
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  escapeHtml(str) {
    if (!str) return ""
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  /**
   * Clear search results
   */
  clearResults() {
    if (this.resultsContainer) {
      this.resultsContainer.innerHTML = ""
      this.resultsContainer.classList.add("hidden")
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
    if (this._documentClickHandler) {
      document.removeEventListener("click", this._documentClickHandler)
    }
  }
}

Object.assign(SearchManager.prototype, visitsResults, createVisitModal)
