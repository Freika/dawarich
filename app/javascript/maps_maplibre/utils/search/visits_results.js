import { translate } from "i18n"

/**
 * Search results for a place: its past visits grouped by year.
 * Mixed into the controller; `this` is the controller.
 */
export const visitsResults = {
  showVisitsLoading(locationName) {
    this.resultsContainer.innerHTML = `
      <div class="p-4 text-sm text-base-content/60">
        <div class="flex items-center gap-2 mb-2">
          <span class="loading loading-spinner loading-sm"></span>
          <span class="font-medium">${translate("search.searching_for_visits")}</span>
        </div>
        <div class="text-xs">${this.escapeHtml(locationName)}</div>
      </div>
    `
    this.resultsContainer.classList.remove("hidden")
  },

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
          <div class="text-sm font-medium">${translate("visits.none_found")}</div>
          <div class="text-xs mt-1">${translate("visits.none_found_for", { query: this.escapeHtml(location.name) })}</div>
        </div>
      `
      this.resultsContainer.classList.remove("hidden")
      return
    }

    // Display visits grouped by location
    let html = `
      <div class="p-4 border-b bg-base-200">
        <div class="text-sm font-medium">${translate("search.locations_found", { count: visitsData.total_locations })}</div>
        <div class="text-xs text-base-content/60 mt-1">${translate("search.for_query", { query: this.escapeHtml(location.name) })}</div>
      </div>
    `

    visitsData.locations.forEach((loc, index) => {
      html += this.buildLocationVisitsHtml(loc, index)
    })

    this.resultsContainer.innerHTML = html
    this.resultsContainer.classList.remove("hidden")

    // Attach event listeners to year toggles and visit items
    this.attachYearToggleListeners()
  },

  /**
   * Build HTML for a location with its visits
   * @param {Object} location - Location with visits
   * @param {number} index - Location index
   * @returns {string} HTML string
   */
  buildLocationVisitsHtml(location, index) {
    const visits = location.visits || []
    if (visits.length === 0) return ""

    // Handle case where visits are sorted newest first
    const sortedVisits = [...visits].sort(
      (a, b) => new Date(a.date) - new Date(b.date),
    )
    const firstVisit = sortedVisits[0]
    const lastVisit = sortedVisits[sortedVisits.length - 1]
    const visitsByYear = this.groupVisitsByYear(visits)

    // Use place_name, address, or coordinates as fallback
    const displayName =
      location.place_name ||
      location.address ||
      translate("map_info.location_coordinates", {
        latitude: location.coordinates?.[0]?.toFixed(4),
        longitude: location.coordinates?.[1]?.toFixed(4),
      })

    return `
      <div class="location-result border-b" data-location-index="${index}">
        <div class="p-4">
          <div class="font-medium text-sm">${this.escapeHtml(displayName)}</div>
          ${
            location.address && location.place_name !== location.address
              ? `<div class="text-xs text-base-content/60 mt-1">${this.escapeHtml(location.address)}</div>`
              : ""
          }
          <div class="flex justify-between items-center mt-3">
            <div class="text-xs text-primary">${translate("selection.visits", { count: location.total_visits })}</div>
            <div class="text-xs text-base-content/60">
              ${translate("search.first_last", { first: this.formatDateShort(firstVisit.date), last: this.formatDateShort(lastVisit.date) })}
            </div>
          </div>
        </div>

        <!-- Years Section -->
        <div class="border-t bg-base-200">
          ${Object.entries(visitsByYear)
            .map(
              ([year, yearVisits]) => `
            <div class="year-section">
              <div class="year-toggle p-3 hover:bg-base-300 cursor-pointer border-b flex justify-between items-center"
                   data-location-index="${index}" data-year="${year}">
                <span class="text-sm font-medium">${year}</span>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-primary">${translate("selection.visits", { count: yearVisits.length })}</span>
                  <span class="year-arrow text-base-content/40 transition-transform">▶</span>
                </div>
              </div>
              <div class="year-visits hidden" id="year-${index}-${year}">
                ${yearVisits
                  .map(
                    (visit) => `
                  <div class="visit-item text-xs py-2 px-4 border-b hover:bg-base-300 cursor-pointer"
                       data-location-index="${index}" data-visit-index="${visits.indexOf(visit)}">
                    <div class="flex justify-between items-start">
                      <div>📍 ${this.formatDateTime(visit.date)}</div>
                      <div class="text-xs text-base-content/60">${visit.duration_estimate || translate("common.not_available")}</div>
                    </div>
                  </div>
                `,
                  )
                  .join("")}
              </div>
            </div>
          `,
            )
            .join("")}
        </div>
      </div>
    `
  },

  /**
   * Group visits by year
   * @param {Array} visits - Array of visits
   * @returns {Object} Visits grouped by year
   */
  groupVisitsByYear(visits) {
    const groups = {}
    visits.forEach((visit) => {
      const year = new Date(visit.date).getFullYear().toString()
      if (!groups[year]) {
        groups[year] = []
      }
      groups[year].push(visit)
    })
    return groups
  },

  /**
   * Attach event listeners to year toggle elements
   */
  attachYearToggleListeners() {
    const toggles = this.resultsContainer.querySelectorAll(".year-toggle")
    toggles.forEach((toggle) => {
      toggle.addEventListener("click", (e) => {
        const locationIndex = e.currentTarget.dataset.locationIndex
        const year = e.currentTarget.dataset.year
        const visitsContainer = document.getElementById(
          `year-${locationIndex}-${year}`,
        )
        const arrow = e.currentTarget.querySelector(".year-arrow")

        if (visitsContainer) {
          visitsContainer.classList.toggle("hidden")
          arrow.style.transform = visitsContainer.classList.contains("hidden")
            ? "rotate(0deg)"
            : "rotate(90deg)"
        }
      })
    })

    // Attach event listeners to individual visit items
    const visitItems = this.resultsContainer.querySelectorAll(".visit-item")
    visitItems.forEach((item) => {
      item.addEventListener("click", (e) => {
        e.stopPropagation()
        const locationIndex = parseInt(item.dataset.locationIndex, 10)
        const visitIndex = parseInt(item.dataset.visitIndex, 10)
        this.handleVisitClick(locationIndex, visitIndex)
      })
    })
  },

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
      duration: 1000,
    })

    // Extract visit details
    const visitDetails = visit.visit_details || {}
    const startTime = visitDetails.start_time || visit.date
    const endTime = visitDetails.end_time || visit.date
    const placeName =
      location.place_name ||
      location.address ||
      translate("search.unnamed_location")

    // Open create visit modal
    this.openCreateVisitModal({
      name: placeName,
      latitude: lat,
      longitude: lon,
      started_at: startTime,
      ended_at: endTime,
    })
  },
}
