import { formatTimestamp } from 'maps_maplibre/utils/geojson_transformers'
import { formatDistance, formatSpeed, minutesToDaysHoursMinutes } from 'maps/helpers'
import maplibregl from 'maplibre-gl'

/**
 * Handles map interaction events (clicks, info display)
 */
export class EventHandlers {
  constructor(map, controller) {
    this.map = map
    this.controller = controller
    this.selectedRouteFeature = null
    this.routeMarkers = [] // Store start/end markers for routes
  }

  /**
   * Handle point click
   */
  handlePointClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        <div><span class="font-semibold">Time:</span> ${formatTimestamp(properties.timestamp, this.controller.timezoneValue)}</div>
        ${properties.battery ? `<div><span class="font-semibold">Battery:</span> ${properties.battery}%</div>` : ''}
        ${properties.altitude ? `<div><span class="font-semibold">Altitude:</span> ${Math.round(properties.altitude)}m</div>` : ''}
        ${properties.velocity ? `<div><span class="font-semibold">Speed:</span> ${Math.round(properties.velocity)} km/h</div>` : ''}
      </div>
    `

    this.controller.showInfo('Location Point', content)
  }

  /**
   * Handle visit click
   */
  handleVisitClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const startTime = formatTimestamp(properties.started_at, this.controller.timezoneValue)
    const endTime = formatTimestamp(properties.ended_at, this.controller.timezoneValue)
    const durationHours = Math.round(properties.duration / 3600)
    const durationDisplay = durationHours >= 1 ? `${durationHours}h` : `${Math.round(properties.duration / 60)}m`

    const content = `
      <div class="space-y-2">
        <div class="badge badge-sm ${properties.status === 'confirmed' ? 'badge-success' : 'badge-warning'}">${properties.status}</div>
        <div><span class="font-semibold">Arrived:</span> ${startTime}</div>
        <div><span class="font-semibold">Left:</span> ${endTime}</div>
        <div><span class="font-semibold">Duration:</span> ${durationDisplay}</div>
      </div>
    `

    const actions = [{
      type: 'button',
      handler: 'handleEdit',
      id: properties.id,
      entityType: 'visit',
      label: 'Edit'
    }]

    this.controller.showInfo(properties.name || properties.place_name || 'Visit', content, actions)
  }

  /**
   * Handle photo click
   */
  handlePhotoClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.photo_url ? `<img src="${properties.photo_url}" alt="Photo" class="w-full rounded-lg mb-2" />` : ''}
        ${properties.taken_at ? `<div><span class="font-semibold">Taken:</span> ${formatTimestamp(properties.taken_at, this.controller.timezoneValue)}</div>` : ''}
      </div>
    `

    this.controller.showInfo('Photo', content)
  }

  /**
   * Handle place click
   */
  handlePlaceClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.tag ? `<div class="badge badge-sm badge-primary">${properties.tag}</div>` : ''}
        ${properties.description ? `<div>${properties.description}</div>` : ''}
      </div>
    `

    const actions = properties.id ? [{
      type: 'button',
      handler: 'handleEdit',
      id: properties.id,
      entityType: 'place',
      label: 'Edit'
    }] : []

    this.controller.showInfo(properties.name || 'Place', content, actions)
  }

  /**
   * Handle area click
   */
  handleAreaClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.radius ? `<div><span class="font-semibold">Radius:</span> ${Math.round(properties.radius)}m</div>` : ''}
        ${properties.latitude && properties.longitude ? `<div><span class="font-semibold">Center:</span> ${properties.latitude.toFixed(6)}, ${properties.longitude.toFixed(6)}</div>` : ''}
      </div>
    `

    const actions = properties.id ? [{
      type: 'button',
      handler: 'handleDelete',
      id: properties.id,
      entityType: 'area',
      label: 'Delete'
    }] : []

    this.controller.showInfo(properties.name || 'Area', content, actions)
  }

  /**
   * Handle route hover
   */
  handleRouteHover(e) {
    const feature = e.features[0]
    if (!feature) return

    const routesLayer = this.controller.layerManager.getLayer('routes')
    if (!routesLayer) return

    // If a route is selected and we're hovering over a different route, show both
    if (this.selectedRouteFeature) {
      // Check if we're hovering over the same route that's selected
      const isSameRoute = this._areFeaturesSame(this.selectedRouteFeature, feature)

      if (!isSameRoute) {
        // Show both selected and hovered routes
        const features = [this.selectedRouteFeature, feature]
        routesLayer.setHoverRoute({
          type: 'FeatureCollection',
          features: features
        })
        // Create markers for both routes
        this._createRouteMarkers(features)
      }
    } else {
      // No selection, just show hovered route
      routesLayer.setHoverRoute(feature)
      // Create markers for hovered route
      this._createRouteMarkers(feature)
    }
  }

  /**
   * Handle route mouse leave
   */
  handleRouteMouseLeave(e) {
    const routesLayer = this.controller.layerManager.getLayer('routes')
    if (!routesLayer) return

    // If a route is selected, keep showing only the selected route
    if (this.selectedRouteFeature) {
      routesLayer.setHoverRoute(this.selectedRouteFeature)
      // Keep markers for selected route only
      this._createRouteMarkers(this.selectedRouteFeature)
    } else {
      // No selection, clear hover and markers
      routesLayer.setHoverRoute(null)
      this._clearRouteMarkers()
    }
  }

  /**
   * Compare two features to see if they represent the same route
   */
  _areFeaturesSame(feature1, feature2) {
    if (!feature1 || !feature2) return false

    // Compare by start/end times and point count (unique enough for routes)
    const props1 = feature1.properties
    const props2 = feature2.properties

    return props1.startTime === props2.startTime &&
           props1.endTime === props2.endTime &&
           props1.pointCount === props2.pointCount
  }

  /**
   * Create start/end markers for route(s)
   * @param {Array|Object} features - Single feature or array of features
   */
  _createRouteMarkers(features) {
    // Clear existing markers first
    this._clearRouteMarkers()

    // Ensure we have an array
    const featureArray = Array.isArray(features) ? features : [features]

    featureArray.forEach(feature => {
      if (!feature || !feature.geometry || feature.geometry.type !== 'LineString') return

      const coords = feature.geometry.coordinates
      if (coords.length < 2) return

      // Start marker (🚥)
      const startCoord = coords[0]
      const startMarker = this._createEmojiMarker('🚥')
      startMarker.setLngLat(startCoord).addTo(this.map)
      this.routeMarkers.push(startMarker)

      // End marker (🏁)
      const endCoord = coords[coords.length - 1]
      const endMarker = this._createEmojiMarker('🏁')
      endMarker.setLngLat(endCoord).addTo(this.map)
      this.routeMarkers.push(endMarker)
    })
  }

  /**
   * Create an emoji marker
   * @param {String} emoji - The emoji to display
   * @returns {maplibregl.Marker}
   */
  _createEmojiMarker(emoji) {
    const el = document.createElement('div')
    el.className = 'route-emoji-marker'
    el.textContent = emoji
    el.style.fontSize = '24px'
    el.style.cursor = 'pointer'
    el.style.userSelect = 'none'

    return new maplibregl.Marker({ element: el, anchor: 'center' })
  }

  /**
   * Clear all route markers
   */
  _clearRouteMarkers() {
    this.routeMarkers.forEach(marker => marker.remove())
    this.routeMarkers = []
  }

  /**
   * Handle route click
   */
  handleRouteClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    // Store selected route
    this.selectedRouteFeature = feature

    // Update hover layer to show selected route
    const routesLayer = this.controller.layerManager.getLayer('routes')
    if (routesLayer) {
      routesLayer.setHoverRoute(feature)
    }

    // Create markers for selected route
    this._createRouteMarkers(feature)

    // Calculate duration
    const durationSeconds = properties.endTime - properties.startTime
    const durationMinutes = Math.floor(durationSeconds / 60)
    const durationFormatted = minutesToDaysHoursMinutes(durationMinutes)

    // Calculate average speed
    let avgSpeed = properties.speed
    if (!avgSpeed && properties.distance > 0 && durationSeconds > 0) {
      avgSpeed = (properties.distance / durationSeconds) * 3600 // km/h
    }

    // Get user preferences
    const distanceUnit = this.controller.settings.distance_unit || 'km'

    // Prepare route data object
    const routeData = {
      startTime: formatTimestamp(properties.startTime, this.controller.timezoneValue),
      endTime: formatTimestamp(properties.endTime, this.controller.timezoneValue),
      duration: durationFormatted,
      distance: formatDistance(properties.distance, distanceUnit),
      speed: avgSpeed ? formatSpeed(avgSpeed, distanceUnit) : null,
      pointCount: properties.pointCount
    }

    // Call controller method to display route info
    this.controller.showRouteInfo(routeData)
  }

  /**
   * Clear route selection
   */
  clearRouteSelection() {
    if (!this.selectedRouteFeature) return

    this.selectedRouteFeature = null

    const routesLayer = this.controller.layerManager.getLayer('routes')
    if (routesLayer) {
      routesLayer.setHoverRoute(null)
    }

    // Clear markers
    this._clearRouteMarkers()

    // Close info panel
    this.controller.closeInfo()
  }
}
