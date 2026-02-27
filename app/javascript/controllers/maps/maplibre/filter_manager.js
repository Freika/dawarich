/**
 * Manages filtering and searching of map data
 */
export class FilterManager {
  constructor(dataLoader) {
    this.dataLoader = dataLoader
    this.currentVisitFilter = "all"
    this.allVisits = []
  }

  /**
   * Store all visits for filtering
   */
  setAllVisits(visits) {
    this.allVisits = visits
  }

  /**
   * Filter and update visits display
   */
  filterAndUpdateVisits(searchTerm, statusFilter, visitsLayer) {
    if (!this.allVisits || !visitsLayer) return

    const filtered = this.allVisits.filter((visit) => {
      // Apply search
      const matchesSearch =
        !searchTerm ||
        visit.name?.toLowerCase().includes(searchTerm) ||
        visit.place?.name?.toLowerCase().includes(searchTerm)

      // Apply status filter
      const matchesStatus =
        statusFilter === "all" || visit.status === statusFilter

      return matchesSearch && matchesStatus
    })

    const geojson = this.dataLoader.visitsToGeoJSON(filtered)
    visitsLayer.update(geojson)
  }

  /**
   * Get current visit filter
   */
  getCurrentVisitFilter() {
    return this.currentVisitFilter
  }

  /**
   * Set current visit filter
   */
  setCurrentVisitFilter(filter) {
    this.currentVisitFilter = filter
  }
}
