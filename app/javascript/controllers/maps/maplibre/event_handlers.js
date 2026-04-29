import maplibregl from "maplibre-gl"
import {
  formatDistance,
  formatSpeed,
  minutesToDaysHoursMinutes,
} from "maps/helpers"
import {
  escapeHtml,
  formatTimeOnly,
  formatTimestamp,
} from "maps_maplibre/utils/geojson_transformers"

/**
 * Handles map interaction events (clicks, info display)
 */
export class EventHandlers {
  constructor(map, controller) {
    this.map = map
    this.controller = controller
    this.selectedRouteFeature = null
    this.selectedTrackFeature = null // Track selection state
    this.routeMarkers = [] // Store start/end markers for routes
    this.trackMarkers = [] // Store segment markers for tracks
    this._infoPanelDelegationSetup = false // Track if delegation is setup

    // Bound handler for track point clicks — stored so the same reference can be
    // used for both map.on() and map.off() during toggle cleanup
    this._handleTrackPointClick = this.handleTrackPointClick.bind(this)
  }

  /**
   * Handle point click — shows instant info from GeoJSON, address loaded via Turbo Frame
   */
  handlePointClick(e) {
    // Check if the click is a follow-on event from a drag operation
    const pointsLayer = this.controller.layerManager.getLayer("points")
    if (pointsLayer?.justDragged) return

    const feature = e.features[0]
    const pointId = feature.properties.id
    const actions = pointId
      ? [
          {
            type: "button",
            handler: "handleDelete",
            id: pointId,
            entityType: "point",
            label: "Delete",
          },
        ]
      : []

    this.controller.showInfo(
      "Location Point",
      this._buildPointInfoContent(feature.properties, feature.geometry),
      actions,
    )
  }

  /**
   * Handle anomaly point click — shows reason and timestamp in the info panel.
   */
  handleAnomalyClick(e) {
    const feature = e.features[0]
    const anomaliesLayer = this.controller.layerManager.getLayer("anomalies")
    if (!anomaliesLayer) return

    const content = anomaliesLayer.buildPopupContent(feature.properties)
    this.controller.showInfo("Anomaly Point", content)
  }

  /**
   * Handle track point click — injects point info into the existing track info panel.
   * Suppresses the event if the user just finished dragging (justDragged flag).
   */
  handleTrackPointClick(e) {
    // Check if the click is a follow-on event from a drag operation
    const trackPointsLayer =
      this.controller.layerManager.getLayer("track-points")
    if (trackPointsLayer?.justDragged) return

    const container = document.getElementById("track-point-info-container")
    if (!container) return

    const feature = e.features[0]
    container.innerHTML = `
      <div class="mt-3 pt-3 border-t border-base-300">
        <div class="text-sm font-semibold mb-1">Selected Point</div>
        ${this._buildPointInfoContent(feature.properties, feature.geometry)}
      </div>
    `
  }

  /**
   * Build HTML content for point info display (shared by regular and track points)
   * Address is loaded asynchronously via a Turbo Frame.
   * @param {Object} properties - GeoJSON feature properties
   * @param {Object} geometry - GeoJSON geometry with coordinates
   * @returns {string} HTML content string
   * @private
   */
  _buildPointInfoContent(properties, geometry) {
    const distanceUnit = this.controller.settings.distance_unit || "km"
    const coords = geometry?.coordinates
    const coordStr =
      coords && coords.length >= 2
        ? `${coords[1].toFixed(6)}, ${coords[0].toFixed(6)}`
        : null
    const pointId = properties.id
    const addressFrame = pointId
      ? `<turbo-frame id="point-address-${pointId}" src="/points/${pointId}/address" loading="lazy"></turbo-frame>`
      : ""
    return `
      <div class="space-y-2">
        ${addressFrame}
        ${coordStr ? `<div><span class="font-semibold">Coordinates:</span> ${coordStr}</div>` : ""}
        <div><span class="font-semibold">Time:</span> ${formatTimestamp(properties.timestamp, this.controller.timezoneValue)}</div>
        ${properties.battery ? `<div><span class="font-semibold">Battery:</span> ${properties.battery}%</div>` : ""}
        ${properties.altitude ? `<div><span class="font-semibold">Altitude:</span> ${Math.round(properties.altitude)}m</div>` : ""}
        ${properties.velocity ? `<div><span class="font-semibold">Speed:</span> ${formatSpeed(properties.velocity * 3.6, distanceUnit)}</div>` : ""}
      </div>
    `
  }

  /**
   * Handle visit click — opens the Timeline tab, selects the visit's day, and
   * queues the visit for halo highlighting. Replaces the old Tools-tab flow
   * (info panel + Edit button) which is gone with the unified timeline.
   */
  handleVisitClick(e) {
    const properties = e.features[0].properties
    const visitId = Number(properties.id)
    const startedAt =
      typeof properties.started_at === "string" ? properties.started_at : null
    const date = startedAt ? startedAt.slice(0, 10) : null

    document.dispatchEvent(
      new CustomEvent("timeline:open-visit", {
        detail: { visitId, date },
      }),
    )
  }

  /**
   * Handle photo click
   */
  handlePhotoClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.photo_url ? `<img src="${escapeHtml(properties.photo_url)}" alt="Photo" class="w-full rounded-lg mb-2" />` : ""}
        ${properties.taken_at ? `<div><span class="font-semibold">Taken:</span> ${formatTimestamp(properties.taken_at, this.controller.timezoneValue)}</div>` : ""}
      </div>
    `

    this.controller.showInfo("Photo", content)
  }

  /**
   * Handle place click
   */
  handlePlaceClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.tag ? `<div class="badge badge-sm badge-primary">${escapeHtml(properties.tag)}</div>` : ""}
        ${properties.description ? `<div>${escapeHtml(properties.description)}</div>` : ""}
      </div>
    `

    const actions = properties.id
      ? [
          {
            type: "button",
            handler: "handleEdit",
            id: properties.id,
            entityType: "place",
            label: "Edit",
          },
        ]
      : []

    this.controller.showInfo(
      escapeHtml(properties.name) || "Place",
      content,
      actions,
    )
  }

  /**
   * Handle area click
   */
  handleAreaClick(e) {
    const feature = e.features[0]
    const properties = feature.properties

    const content = `
      <div class="space-y-2">
        ${properties.radius ? `<div><span class="font-semibold">Radius:</span> ${Math.round(properties.radius)}m</div>` : ""}
        ${properties.latitude && properties.longitude ? `<div><span class="font-semibold">Center:</span> ${properties.latitude.toFixed(6)}, ${properties.longitude.toFixed(6)}</div>` : ""}
      </div>
    `

    const actions = properties.id
      ? [
          {
            type: "button",
            handler: "handleDelete",
            id: properties.id,
            entityType: "area",
            label: "Delete",
          },
        ]
      : []

    this.controller.showInfo(
      escapeHtml(properties.name) || "Area",
      content,
      actions,
    )
  }

  /**
   * Handle route hover
   */
  handleRouteHover(e) {
    const clickedFeature = e.features[0]
    if (!clickedFeature) return

    const routesLayer = this.controller.layerManager.getLayer("routes")
    if (!routesLayer) return

    // Get the full feature from source (not the clipped tile version)
    // Fallback to clipped feature if full feature not found
    const fullFeature =
      this._getFullRouteFeature(clickedFeature.properties) || clickedFeature

    // If a route is selected and we're hovering over a different route, show both
    if (this.selectedRouteFeature) {
      // Check if we're hovering over the same route that's selected
      const isSameRoute = this._areFeaturesSame(
        this.selectedRouteFeature,
        fullFeature,
      )

      if (!isSameRoute) {
        // Show both selected and hovered routes
        const features = [this.selectedRouteFeature, fullFeature]
        routesLayer.setHoverRoute({
          type: "FeatureCollection",
          features: features,
        })
        // Create markers for both routes
        this._createRouteMarkers(features)
      }
    } else {
      // No selection, just show hovered route
      routesLayer.setHoverRoute(fullFeature)
      // Create markers for hovered route
      this._createRouteMarkers(fullFeature)
    }
  }

  /**
   * Handle route mouse leave
   */
  handleRouteMouseLeave() {
    const routesLayer = this.controller.layerManager.getLayer("routes")
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
   * Get full route feature from source data (not clipped tile version)
   * MapLibre returns clipped geometries from queryRenderedFeatures()
   * We need the full geometry from the source for proper highlighting
   */
  _getFullRouteFeature(properties) {
    const routesLayer = this.controller.layerManager.getLayer("routes")
    if (!routesLayer) return null

    const source = this.map.getSource(routesLayer.sourceId)
    if (!source) return null

    // Get the source data (GeoJSON FeatureCollection)
    // Try multiple ways to access the data
    let sourceData = null

    // Method 1: Serialize via public API (preferred)
    if (source.serialize) {
      const serialized = source.serialize()
      sourceData = serialized.data
    }
    // Method 2: Use cached data from layer
    else if (routesLayer.data) {
      sourceData = routesLayer.data
    }

    if (!sourceData || !sourceData.features) return null

    // Find the matching feature by properties
    // First try to match by unique ID (most reliable)
    if (properties.id) {
      const featureById = sourceData.features.find(
        (f) => f.properties.id === properties.id,
      )
      if (featureById) return featureById
    }
    if (properties.routeId) {
      const featureByRouteId = sourceData.features.find(
        (f) => f.properties.routeId === properties.routeId,
      )
      if (featureByRouteId) return featureByRouteId
    }

    // Fall back to matching by start/end times and point count
    return sourceData.features.find((feature) => {
      const props = feature.properties
      return (
        props.startTime === properties.startTime &&
        props.endTime === properties.endTime &&
        props.pointCount === properties.pointCount
      )
    })
  }

  /**
   * Compare two features to see if they represent the same route
   */
  _areFeaturesSame(feature1, feature2) {
    if (!feature1 || !feature2) return false

    const props1 = feature1.properties
    const props2 = feature2.properties

    // First check for unique route identifier (most reliable)
    if (props1.id && props2.id) {
      return props1.id === props2.id
    }
    if (props1.routeId && props2.routeId) {
      return props1.routeId === props2.routeId
    }

    // Fall back to comparing start/end times and point count
    return (
      props1.startTime === props2.startTime &&
      props1.endTime === props2.endTime &&
      props1.pointCount === props2.pointCount
    )
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

    featureArray.forEach((feature) => {
      if (
        !feature ||
        !feature.geometry ||
        feature.geometry.type !== "LineString"
      )
        return

      const coords = feature.geometry.coordinates
      if (coords.length < 2) return

      // Start marker (🚥)
      const startCoord = coords[0]
      const startMarker = this._createEmojiMarker("🚥")
      startMarker.setLngLat(startCoord).addTo(this.map)
      this.routeMarkers.push(startMarker)

      // End marker (🏁)
      const endCoord = coords[coords.length - 1]
      const endMarker = this._createEmojiMarker("🏁")
      endMarker.setLngLat(endCoord).addTo(this.map)
      this.routeMarkers.push(endMarker)
    })
  }

  /**
   * Create an emoji marker
   * @param {String} emoji - The emoji to display
   * @param {String} markerClass - CSS class for the marker (default: 'route-emoji-marker')
   * @returns {maplibregl.Marker}
   */
  _createEmojiMarker(emoji, markerClass = "route-emoji-marker") {
    const el = document.createElement("div")
    el.className = markerClass
    el.textContent = emoji
    el.style.fontSize = "24px"
    el.style.cursor = "pointer"
    el.style.userSelect = "none"

    return new maplibregl.Marker({ element: el, anchor: "center" })
  }

  /**
   * Clear all route markers
   */
  _clearRouteMarkers() {
    for (const marker of this.routeMarkers) {
      marker.remove()
    }
    this.routeMarkers = []
  }

  /**
   * Handle route click
   */
  handleRouteClick(e) {
    // Points take priority — if a point exists at this location, let handlePointClick handle it
    if (this.map.getLayer("points")) {
      const pointFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["points"],
      })
      if (pointFeatures.length > 0) return
    }

    const clickedFeature = e.features[0]
    const properties = clickedFeature.properties

    // Get the full feature from source (not the clipped tile version)
    // Fallback to clipped feature if full feature not found
    const fullFeature = this._getFullRouteFeature(properties) || clickedFeature

    // Store selected route (use full feature)
    this.selectedRouteFeature = fullFeature

    // Update hover layer to show selected route
    const routesLayer = this.controller.layerManager.getLayer("routes")
    if (routesLayer) {
      routesLayer.setHoverRoute(fullFeature)
    }

    // Create markers for selected route
    this._createRouteMarkers(fullFeature)

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
    const distanceUnit = this.controller.settings.distance_unit || "km"

    // Prepare route data object
    const routeData = {
      startTime: formatTimestamp(
        properties.startTime,
        this.controller.timezoneValue,
      ),
      endTime: formatTimestamp(
        properties.endTime,
        this.controller.timezoneValue,
      ),
      duration: durationFormatted,
      distance: formatDistance(properties.distance, distanceUnit),
      speed: avgSpeed ? formatSpeed(avgSpeed, distanceUnit) : null,
      pointCount: properties.pointCount,
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

    const routesLayer = this.controller.layerManager.getLayer("routes")
    if (routesLayer) {
      routesLayer.setHoverRoute(null)
    }

    // Clear markers
    this._clearRouteMarkers()

    // Close info panel
    this.controller.closeInfo()
  }

  /**
   * Handle track click — opens the Timeline tab, navigates to the track's day,
   * and expands the matching journey entry so the track's full details
   * (distance, speed, elevation, replay, show-points toggle) are shown inline.
   * Replaces the old Tools-tab flow.
   */
  handleTrackClick(e) {
    // Points take priority over tracks
    if (this.map.getLayer("points")) {
      const pointFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["points"],
      })
      if (pointFeatures.length > 0) return
    }

    // Routes take priority over tracks
    if (this.map.getLayer("routes-hit")) {
      const routeFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["routes-hit"],
      })
      if (routeFeatures.length > 0) return
    }

    // Track points take priority over tracks — clicking a point shows point info, not track info
    if (this.map.getLayer("track-points")) {
      const trackPointFeatures = this.map.queryRenderedFeatures(e.point, {
        layers: ["track-points"],
      })
      if (trackPointFeatures.length > 0) return
    }

    const clickedFeature = e.features[0]
    if (!clickedFeature) return

    const properties = clickedFeature.properties
    const fullFeature = this._getFullTrackFeature(properties) || clickedFeature
    this.selectedTrackFeature = fullFeature

    // Keep the on-map highlight + segment visualization — those are visual
    // feedback for the click itself, independent of the info surface.
    try {
      const tracksLayer = this.controller.layerManager.getLayer("tracks")
      if (tracksLayer?.setSelectedTrack) {
        tracksLayer.setSelectedTrack(fullFeature)
      }
    } catch (err) {
      console.warn("[EventHandlers] Failed to highlight track:", err)
    }
    this._loadTrackSegments(properties.id, fullFeature)

    // Derive the day from the track's start. `start_at` comes from our own
    // serializer as an ISO8601 string — safe to slice the date portion.
    const startAt =
      typeof properties.start_at === "string" ? properties.start_at : null
    const date = startAt ? startAt.slice(0, 10) : null
    const trackId = Number(properties.id)

    document.dispatchEvent(
      new CustomEvent("timeline:open-track", {
        detail: { trackId, date, startAt },
      }),
    )
  }

  /**
   * Load track segments from API (lazy loading)
   * @private
   */
  async _loadTrackSegments(trackId, fullFeature) {
    const segmentsContainer = document.getElementById(
      "track-segments-container",
    )

    try {
      // Fetch track with segments from API
      const trackFeature =
        await this.controller.api.fetchTrackWithSegments(trackId)

      if (!trackFeature) {
        console.warn("Failed to fetch track segments")
        if (segmentsContainer) {
          segmentsContainer.textContent = "No segments available"
        }
        return
      }

      // Parse segments from the fetched track
      let segments = []
      try {
        const props = trackFeature.properties
        segments =
          typeof props.segments === "string"
            ? JSON.parse(props.segments)
            : props.segments || []
      } catch (err) {
        console.warn("Failed to parse track segments:", err)
      }

      // Update tracks layer to show segment highlighting
      const tracksLayer = this.controller.layerManager.getLayer("tracks")
      if (tracksLayer?.showSegments) {
        tracksLayer.showSegments(fullFeature, segments)

        // Set up callbacks for map segment hover → list highlight
        tracksLayer.setSegmentHoverCallback((segmentIndex) => {
          this._highlightSegmentOnMap(segmentIndex)
          this._highlightSegmentListItem(segmentIndex)
        })

        tracksLayer.setSegmentLeaveCallback(() => {
          this._clearSegmentHighlight()
          this._clearSegmentListHighlight()
        })
      }

      // Create segment markers with emojis
      this._createTrackSegmentMarkers(fullFeature, segments)

      // Update segments list in info panel
      this._updateSegmentsList(segments)

      // Set up hover event listeners for segment list items
      this._setupSegmentListHover(segments)
    } catch (error) {
      console.error("Failed to load track segments:", error)
      if (segmentsContainer) {
        segmentsContainer.textContent = "Failed to load segments"
      }
    }
  }

  /**
   * Show track info panel with basic info (segments loaded separately)
   * @private
   */
  _showTrackInfoPanel(properties) {
    const distanceUnit = this.controller.settings.distance_unit || "km"
    const durationMinutes = Math.floor((properties.duration || 0) / 60)
    const trackDistanceKm = (properties.distance || 0) / 1000

    // Build content using template - data comes from our own trusted backend
    const content = this._buildTrackInfoContent(
      properties,
      distanceUnit,
      durationMinutes,
      trackDistanceKm,
    )

    this.controller.showInfo(`Track #${properties.id}`, content)

    // Set up the show points toggle handler (uses event delegation)
    this._setupTrackPointsToggle()
  }

  /**
   * Build track info panel HTML content
   * Note: Data comes from our own backend API, not user input
   * @private
   */
  _buildTrackInfoContent(
    properties,
    distanceUnit,
    durationMinutes,
    trackDistanceKm,
  ) {
    const showPointsToggle = `
      <div class="form-control mt-3 pt-3 border-t border-base-300">
        <label class="label cursor-pointer justify-start gap-3 py-1">
          <input type="checkbox"
                 id="track-points-toggle"
                 class="toggle toggle-sm toggle-success"
                 data-track-id="${properties.id}" />
          <span class="label-text font-medium">Show Points</span>
        </label>
        <p class="text-xs text-base-content/60 ml-10">Enable to view and drag points to edit track</p>
      </div>
    `

    const replayButton = `
      <div class="mt-3 pt-3 border-t border-base-300">
        <button id="track-replay-button"
                class="btn btn-sm btn-primary gap-2"
                data-action="click->maps--maplibre#replayTrack"
                data-track-start="${properties.start_at}">
          <svg id="track-replay-play-icon" xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" />
          </svg>
          <svg id="track-replay-pause-icon" xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 hidden" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM7 8a1 1 0 012 0v4a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v4a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
          </svg>
          <span id="track-replay-label">Replay</span>
        </button>
      </div>
    `

    return `
      <div class="space-y-2">
        <div><span class="font-semibold">Start:</span> ${formatTimestamp(properties.start_at, this.controller.timezoneValue)}</div>
        <div><span class="font-semibold">End:</span> ${formatTimestamp(properties.end_at, this.controller.timezoneValue)}</div>
        <div><span class="font-semibold">Duration:</span> ${minutesToDaysHoursMinutes(durationMinutes)}</div>
        <div><span class="font-semibold">Distance:</span> ${formatDistance(trackDistanceKm, distanceUnit)}</div>
        <div><span class="font-semibold">Avg Speed:</span> ${formatSpeed(properties.avg_speed || 0, distanceUnit)}</div>
        ${properties.dominant_mode ? `<div><span class="font-semibold">Mode:</span> ${escapeHtml(properties.dominant_mode_emoji)} ${escapeHtml(properties.dominant_mode)}</div>` : ""}
        ${showPointsToggle}
        <div id="track-point-info-container"></div>
        ${replayButton}
        <div id="track-segments-container" class="mt-2">
          <div class="flex items-center gap-2 text-sm text-base-content/60">
            <span class="loading loading-spinner loading-xs"></span>
            Loading segments...
          </div>
        </div>
      </div>
    `
  }

  /**
   * Update segments list in the info panel after lazy loading
   * Note: Data comes from our own backend API, not user input
   * @private
   */
  _updateSegmentsList(segments) {
    const segmentsContainer = document.getElementById(
      "track-segments-container",
    )
    if (!segmentsContainer) return

    if (segments.length === 0) {
      segmentsContainer.textContent = "No segments"
      return
    }

    const distanceUnit = this.controller.settings.distance_unit || "km"

    // Build segments list HTML - data is from our trusted backend
    const segmentsHtml = segments
      .map(
        (s, idx) => `
        <li class="flex items-center gap-2 px-2 py-1 rounded cursor-pointer transition-colors hover:bg-base-200 segment-list-item"
            data-segment-index="${idx}"
            data-segment-mode="${s.mode}">
          <span class="text-xs opacity-60 font-mono w-24">${formatTimeOnly(s.start_time, this.controller.timezoneValue)} - ${formatTimeOnly(s.end_time, this.controller.timezoneValue)}</span>
          <span>${escapeHtml(s.emoji)}</span>
          <span class="capitalize flex-1">${escapeHtml(s.mode)}</span>
          <span class="text-xs opacity-70">${formatDistance((s.distance || 0) / 1000, distanceUnit)}</span>
        </li>
      `,
      )
      .join("")

    // Using innerHTML for trusted backend data only
    segmentsContainer.innerHTML = `
      <div class="mt-2">
        <span class="font-semibold">Segments:</span>
        <ul id="track-segments-list" class="list-none pl-0 mt-1 space-y-1">
          ${segmentsHtml}
        </ul>
      </div>
    `
  }

  /**
   * Clear track selection
   */
  clearTrackSelection() {
    if (!this.selectedTrackFeature) return

    this.selectedTrackFeature = null

    const tracksLayer = this.controller.layerManager.getLayer("tracks")
    if (tracksLayer) {
      // Clear selection highlight
      if (tracksLayer.setSelectedTrack) {
        tracksLayer.setSelectedTrack(null)
      }
      if (tracksLayer.hideSegments) {
        tracksLayer.hideSegments()
      }
      // Clear hover callbacks
      tracksLayer.setSegmentHoverCallback(null)
      tracksLayer.setSegmentLeaveCallback(null)
    }

    // Clear track points layer
    this._clearTrackPointsLayer()

    // Restore main points layer opacity
    this._setMainPointsOpacity(1.0)

    // Clear segment markers
    this._clearTrackMarkers()

    // Clean up segment list listeners
    this._cleanupSegmentListHover()

    // Close info panel
    this.controller.closeInfo()
  }

  /**
   * Set up the track points toggle handler using event delegation
   * Uses delegation on info panel container to reliably catch toggle changes
   * regardless of DOM timing
   */
  _setupTrackPointsToggle() {
    // Only set up delegation once
    if (this._infoPanelDelegationSetup) return

    const infoDisplay = this.controller.infoDisplayTarget
    if (!infoDisplay) return

    // Use event delegation - listen for changes on the container
    infoDisplay.addEventListener("change", async (e) => {
      if (e.target.id === "track-points-toggle") {
        const trackId = e.target.dataset.trackId
        const enabled = e.target.checked
        await this._toggleTrackPoints(trackId, enabled)
      }
    })

    this._infoPanelDelegationSetup = true
  }

  /**
   * Toggle track points layer visibility
   * @param {number} trackId - Track ID
   * @param {boolean} enabled - Whether to show or hide points
   */
  async _toggleTrackPoints(trackId, enabled) {
    if (enabled) {
      // Dim the main points layer
      this._setMainPointsOpacity(0.3)

      // Get or create track points layer
      let trackPointsLayer =
        this.controller.layerManager.getLayer("track-points")

      if (!trackPointsLayer) {
        // Import and create the layer dynamically
        const { TrackPointsLayer } = await import(
          "maps_maplibre/layers/track_points_layer"
        )
        trackPointsLayer = new TrackPointsLayer(this.map, {
          apiClient: this.controller.api,
        })
        this.controller.layerManager.registerLayer(
          "track-points",
          trackPointsLayer,
        )
      }

      // Load track points
      await trackPointsLayer.loadTrackPoints(trackId)

      // Register click handler for track points (shows point info on click)
      this.map.on("click", "track-points", this._handleTrackPointClick)
    } else {
      // Clear track points layer
      this._clearTrackPointsLayer()

      // Restore main points layer opacity
      this._setMainPointsOpacity(1.0)
    }
  }

  /**
   * Clear the track points layer and remove its click handler
   */
  _clearTrackPointsLayer() {
    // Remove the click handler before clearing the layer
    this.map.off("click", "track-points", this._handleTrackPointClick)

    const trackPointsLayer =
      this.controller.layerManager.getLayer("track-points")
    if (trackPointsLayer) {
      trackPointsLayer.clear()
    }
  }

  /**
   * Set the opacity of the main points layer
   * @param {number} opacity - Opacity value (0-1)
   */
  _setMainPointsOpacity(opacity) {
    const pointsLayer = this.controller.layerManager.getLayer("points")
    if (pointsLayer && this.map.getLayer(pointsLayer.id)) {
      this.map.setPaintProperty(pointsLayer.id, "circle-opacity", opacity)
      this.map.setPaintProperty(
        pointsLayer.id,
        "circle-stroke-opacity",
        opacity,
      )
    }
  }

  /**
   * Get full track feature from source data
   */
  _getFullTrackFeature(properties) {
    const tracksLayer = this.controller.layerManager.getLayer("tracks")
    if (!tracksLayer) return null

    const source = this.map.getSource(tracksLayer.sourceId)
    if (!source) return null

    let sourceData = null
    if (source.serialize) {
      sourceData = source.serialize().data
    } else if (tracksLayer.data) {
      sourceData = tracksLayer.data
    }

    if (!sourceData || !sourceData.features) return null

    // Find by track ID
    if (properties.id) {
      return sourceData.features.find((f) => f.properties.id === properties.id)
    }

    return null
  }

  /**
   * Create emoji markers at segment transition points
   */
  _createTrackSegmentMarkers(feature, segments) {
    this._clearTrackMarkers()

    if (!feature || !feature.geometry || feature.geometry.type !== "LineString")
      return
    if (!segments || segments.length === 0) return

    const coords = feature.geometry.coordinates
    if (coords.length < 2) return

    // Add marker at start of each segment
    segments.forEach((segment) => {
      const coordIndex = Math.min(segment.start_index || 0, coords.length - 1)
      const coord = coords[coordIndex]
      if (!coord) return

      const marker = this._createEmojiMarker(
        segment.emoji || "❓",
        "track-emoji-marker",
      )
      marker.setLngLat(coord).addTo(this.map)
      this.trackMarkers.push(marker)
    })

    // Add end marker (🏁) at the last point
    const endCoord = coords[coords.length - 1]
    const endMarker = this._createEmojiMarker("🏁", "track-emoji-marker")
    endMarker.setLngLat(endCoord).addTo(this.map)
    this.trackMarkers.push(endMarker)
  }

  /**
   * Clear all track segment markers
   */
  _clearTrackMarkers() {
    for (const marker of this.trackMarkers) {
      marker.remove()
    }
    this.trackMarkers = []
  }

  /**
   * Update track segment markers when track geometry changes
   * Called after track recalculation to move emoji markers to new positions
   * @param {Object} feature - The updated track GeoJSON feature
   */
  updateTrackMarkers(feature) {
    if (!this.selectedTrackFeature) return
    if (!feature || !feature.geometry || feature.geometry.type !== "LineString")
      return

    // Parse segments from feature properties
    let segments = []
    try {
      const props = feature.properties || {}
      segments =
        typeof props.segments === "string"
          ? JSON.parse(props.segments)
          : props.segments || []
    } catch (err) {
      console.warn("Failed to parse track segments for marker update:", err)
      return
    }

    // Recreate markers with new coordinates
    this._createTrackSegmentMarkers(feature, segments)
  }

  /**
   * Clean up segment list hover/click listeners and pending timeout
   * @private
   */
  _cleanupSegmentListHover() {
    if (this._segmentListTimeout) {
      clearTimeout(this._segmentListTimeout)
      this._segmentListTimeout = null
    }

    if (this._segmentListListeners) {
      this._segmentListListeners.forEach(({ element, event, handler }) => {
        element.removeEventListener(event, handler)
      })
      this._segmentListListeners = null
    }
  }

  /**
   * Set up hover and click event listeners for segment list items in the info panel
   * @param {Array} segments - Array of segment data
   */
  _setupSegmentListHover(segments) {
    // Clean up any existing listeners first
    this._cleanupSegmentListHover()

    // Use setTimeout to ensure the DOM has been updated
    this._segmentListTimeout = setTimeout(() => {
      this._segmentListTimeout = null
      const listItems = document.querySelectorAll(".segment-list-item")
      this._segmentListListeners = []

      listItems.forEach((item) => {
        const segmentIndex = parseInt(item.dataset.segmentIndex, 10)

        const enterHandler = () => {
          this._highlightSegmentOnMap(segmentIndex)
          this._highlightSegmentListItem(segmentIndex)
        }

        const leaveHandler = () => {
          this._clearSegmentHighlight()
          this._clearSegmentListHighlight()
        }

        const clickHandler = () => {
          this._zoomToSegment(segments[segmentIndex])
        }

        item.addEventListener("mouseenter", enterHandler)
        item.addEventListener("mouseleave", leaveHandler)
        item.addEventListener("click", clickHandler)

        this._segmentListListeners.push(
          { element: item, event: "mouseenter", handler: enterHandler },
          { element: item, event: "mouseleave", handler: leaveHandler },
          { element: item, event: "click", handler: clickHandler },
        )
      })
    }, 50)
  }

  /**
   * Zoom the map to fit a specific segment's bounds
   * @param {Object} segment - Segment data with start_index and end_index
   */
  _zoomToSegment(segment) {
    if (!this.selectedTrackFeature || !segment) return

    const coords = this.selectedTrackFeature.geometry?.coordinates
    if (!coords || coords.length < 2) return

    const startIdx = Math.max(0, segment.start_index || 0)
    const endIdx = Math.min(coords.length - 1, segment.end_index || startIdx)

    // Extract coordinates for this segment
    const segmentCoords = coords.slice(startIdx, endIdx + 1)
    if (segmentCoords.length < 1) return

    // Build bounds from segment coordinates
    const bounds = new maplibregl.LngLatBounds()
    segmentCoords.forEach((coord) => {
      bounds.extend(coord)
    })

    // Fit map to segment bounds
    this.map.fitBounds(bounds, {
      padding: 80,
      maxZoom: 17,
      duration: 500,
    })
  }

  /**
   * Highlight a specific segment on the map
   * @param {number} segmentIndex - Index of the segment to highlight
   */
  _highlightSegmentOnMap(segmentIndex) {
    const tracksLayer = this.controller.layerManager.getLayer("tracks")
    if (!tracksLayer) return

    const segmentLayerId = tracksLayer.segmentLayerId
    if (!this.map.getLayer(segmentLayerId)) return

    // Increase opacity/width of hovered segment, dim others
    this.map.setPaintProperty(segmentLayerId, "line-opacity", [
      "case",
      ["==", ["get", "segmentIndex"], segmentIndex],
      1.0,
      0.4,
    ])
    this.map.setPaintProperty(segmentLayerId, "line-width", [
      "case",
      ["==", ["get", "segmentIndex"], segmentIndex],
      8,
      4,
    ])
  }

  /**
   * Clear segment highlight on map
   */
  _clearSegmentHighlight() {
    const tracksLayer = this.controller.layerManager.getLayer("tracks")
    if (!tracksLayer) return

    const segmentLayerId = tracksLayer.segmentLayerId
    if (!this.map.getLayer(segmentLayerId)) return

    // Reset to uniform appearance
    this.map.setPaintProperty(segmentLayerId, "line-opacity", 0.9)
    this.map.setPaintProperty(segmentLayerId, "line-width", 6)
  }

  /**
   * Highlight a segment list item in the info panel
   * @param {number} segmentIndex - Index of the segment to highlight
   */
  _highlightSegmentListItem(segmentIndex) {
    const listItems = document.querySelectorAll(".segment-list-item")
    listItems.forEach((item) => {
      if (parseInt(item.dataset.segmentIndex, 10) === segmentIndex) {
        item.classList.add("bg-primary", "bg-opacity-20")
      } else {
        item.classList.add("opacity-50")
      }
    })
  }

  /**
   * Clear segment list item highlight
   */
  _clearSegmentListHighlight() {
    const listItems = document.querySelectorAll(".segment-list-item")
    listItems.forEach((item) => {
      item.classList.remove("bg-primary", "bg-opacity-20", "opacity-50")
    })
  }
}
