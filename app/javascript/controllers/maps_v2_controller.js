import { Controller } from '@hotwired/stimulus'
import maplibregl from 'maplibre-gl'
import { ApiClient } from 'maps_v2/services/api_client'
import { PointsLayer } from 'maps_v2/layers/points_layer'
import { pointsToGeoJSON } from 'maps_v2/utils/geojson_transformers'
import { PopupFactory } from 'maps_v2/components/popup_factory'

/**
 * Main map controller for Maps V2
 * Phase 1: MVP with points layer
 */
export default class extends Controller {
  static values = {
    apiKey: String,
    startDate: String,
    endDate: String
  }

  static targets = ['container', 'loading', 'monthSelect']

  connect() {
    this.initializeMap()
    this.initializeAPI()
    this.loadMapData()
  }

  disconnect() {
    this.map?.remove()
  }

  /**
   * Initialize MapLibre map
   */
  initializeMap() {
    this.map = new maplibregl.Map({
      container: this.containerTarget,
      style: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json',
      center: [0, 0],
      zoom: 2
    })

    // Add navigation controls
    this.map.addControl(new maplibregl.NavigationControl(), 'top-right')

    // Setup click handler for points
    this.map.on('click', 'points', this.handlePointClick.bind(this))

    // Change cursor on hover
    this.map.on('mouseenter', 'points', () => {
      this.map.getCanvas().style.cursor = 'pointer'
    })
    this.map.on('mouseleave', 'points', () => {
      this.map.getCanvas().style.cursor = ''
    })
  }

  /**
   * Initialize API client
   */
  initializeAPI() {
    this.api = new ApiClient(this.apiKeyValue)
  }

  /**
   * Load points data from API
   */
  async loadMapData() {
    this.showLoading()

    try {
      // Fetch all points for selected month
      const points = await this.api.fetchAllPoints({
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        onProgress: this.updateLoadingProgress.bind(this)
      })

      console.log(`Loaded ${points.length} points`)

      // Transform to GeoJSON
      const geojson = pointsToGeoJSON(points)

      // Create/update points layer
      if (!this.pointsLayer) {
        this.pointsLayer = new PointsLayer(this.map)

        // Wait for map to load before adding layer
        if (this.map.loaded()) {
          this.pointsLayer.add(geojson)
        } else {
          this.map.on('load', () => {
            this.pointsLayer.add(geojson)
          })
        }
      } else {
        this.pointsLayer.update(geojson)
      }

      // Fit map to data bounds
      if (points.length > 0) {
        this.fitMapToBounds(geojson)
      }

    } catch (error) {
      console.error('Failed to load map data:', error)
      alert('Failed to load location data. Please try again.')
    } finally {
      this.hideLoading()
    }
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const coordinates = feature.geometry.coordinates.slice()
    const properties = feature.properties

    // Create popup
    new maplibregl.Popup()
      .setLngLat(coordinates)
      .setHTML(PopupFactory.createPointPopup(properties))
      .addTo(this.map)
  }

  /**
   * Fit map to data bounds
   */
  fitMapToBounds(geojson) {
    const coordinates = geojson.features.map(f => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    this.map.fitBounds(bounds, {
      padding: 50,
      maxZoom: 15
    })
  }

  /**
   * Month selector changed
   */
  monthChanged(event) {
    const [year, month] = event.target.value.split('-')

    // Update date values
    this.startDateValue = `${year}-${month}-01T00:00:00Z`
    const lastDay = new Date(year, month, 0).getDate()
    this.endDateValue = `${year}-${month}-${lastDay}T23:59:59Z`

    // Reload data
    this.loadMapData()
  }

  /**
   * Show loading indicator
   */
  showLoading() {
    this.loadingTarget.classList.remove('hidden')
  }

  /**
   * Hide loading indicator
   */
  hideLoading() {
    this.loadingTarget.classList.add('hidden')
  }

  /**
   * Update loading progress
   */
  updateLoadingProgress({ loaded, totalPages, progress }) {
    const percentage = Math.round(progress * 100)
    this.loadingTarget.textContent = `Loading... ${percentage}%`
  }
}
