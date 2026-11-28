import { timeOverlapOpacityExpr } from "maps_maplibre/utils/time_overlap"
import { DateManager } from "./date_manager"

const TIMELINE_EVENTS = {
  "timeline-feed:day-expanded": "handleDayExpanded",
  "timeline-feed:day-collapsed": "handleDayCollapsed",
  "timeline-feed:entry-hover": "handleEntryHover",
  "timeline-feed:entry-unhover": "handleEntryUnhover",
  "timeline-feed:entry-click": "handleEntryClick",
  "timeline-feed:entry-deselect": "handleEntryDeselect",
}

/** What the timeline feed has in focus (a day or an entry), shown on the map. */
export class TimelineMapBridge {
  constructor(controller) {
    this.controller = controller
    this.highlightedDay = null
    this._selectionVersion = 0
    this._visitsOverride = null
  }

  get map() {
    return this.controller.map
  }

  get layerManager() {
    return this.controller.layerManager
  }

  get api() {
    return this.controller.api
  }

  get filterManager() {
    return this.controller.filterManager
  }

  get dataLoader() {
    return this.controller.dataLoader
  }

  connect(cleanup) {
    for (const [eventName, handler] of Object.entries(TIMELINE_EVENTS)) {
      cleanup.addEventListener(document, eventName, this[handler].bind(this))
    }
  }

  /**
   * Handle day-expanded events from the timeline-feed controller.
   * Fits the map to the day's bounding box and dims non-matching features.
   */
  handleDayExpanded(event) {
    const { bounds, day } = event.detail
    if (!this.map) return

    if (bounds) {
      const { sw_lat, sw_lng, ne_lat, ne_lng } = bounds
      this.map.fitBounds(
        [
          [sw_lng, sw_lat],
          [ne_lng, ne_lat],
        ],
        { padding: 60, maxZoom: 15, duration: 800 },
      )
    }

    if (day) {
      this.applyDayHighlight(day)
      this._showDayVisits(day)
      // The selected day is shared: replay jumps to it, the totals count it.
      this.controller.replayPanel?.syncToDay(day)
      this.controller.rangeStatistics?.load(
        DateManager.formatDateForAPI(new Date(`${day}T00:00:00`)),
        DateManager.formatDateForAPI(new Date(`${day}T23:59:59`)),
      )
    }
  }

  /**
   * Handle day-collapsed events — restore full opacity on all layers.
   */
  handleDayCollapsed() {
    this.clearDayHighlight()
    this.controller.rangeStatistics?.load(
      this.controller.startDateValue,
      this.controller.endDateValue,
    )
  }

  /**
   * Dim non-matching features for the selected day.
   * Tile-backed Tracks and Points use Unix timestamps (seconds);
   * visits use ISO 8601 strings (lexicographically sortable).
   * @param {string} day - Date string "YYYY-MM-DD"
   * @private
   */
  applyDayHighlight(day) {
    if (!this.map) return

    this.highlightedDay = day
    const DIM = 0.04

    // Compute day boundaries as Unix seconds
    const dayStart = new Date(`${day}T00:00:00`).getTime() / 1000
    const dayEnd = new Date(`${day}T23:59:59`).getTime() / 1000

    // ISO boundaries for visit layers (lexicographic comparison)
    const isoStart = `${day}T00:00:00`
    const isoEnd = `${day}T23:59:59`

    this._dimTracksAndPoints(dayStart, dayEnd, DIM)

    // Visits: started_at is ISO 8601 string
    const visitExpr = this._dayRangeExpr(
      "started_at",
      isoStart,
      isoEnd,
      0.9,
      DIM,
    )
    this._safeSetPaint("visits", "circle-opacity", visitExpr)
    this._safeSetPaint("visits", "circle-stroke-opacity", visitExpr)

    // Visit labels
    this.layerManager.getLayer("visits")?.setLabelOpacity((f) => {
      const startedAt = f.properties.started_at
      return startedAt >= isoStart && startedAt < isoEnd ? 1 : DIM
    })
  }

  /**
   * Restore default opacity on all layers.
   * @private
   */
  clearDayHighlight() {
    if (!this.map) return

    this.highlightedDay = null
    this._hideDayVisits()
    this._safeSetPaint("tracks-mvt", "line-opacity", 1)
    this._safeSetPaint("points-mvt", "circle-opacity", 1)
    this._safeSetPaint("points-mvt", "circle-stroke-opacity", 1)
    this._safeSetPaint("visits", "circle-opacity", 0.9)
    this._safeSetPaint("visits", "circle-stroke-opacity", 1)
    this.layerManager.getLayer("visits")?.setLabelOpacity(null)
  }

  /**
   * Handle entry-hover events from the timeline feed.
   * Highlights the matching route/visit on the map by dimming everything else.
   */
  handleEntryHover(event) {
    const { entryType, startedAt, endedAt, visitId } = event.detail
    if (!this.map || !startedAt || !endedAt) return

    const DIM = 0.08
    const startUnix = new Date(startedAt).getTime() / 1000
    const endUnix = new Date(endedAt).getTime() / 1000
    this._dimTracksAndPoints(startUnix, endUnix, DIM)

    // Visits:
    //   - Visit hover  → only the hovered visit stays full opacity; others are
    //     dimmed so the on-map dot the rail row points to is unambiguous.
    //   - Journey hover → no visit is the focus, so all visits fade nearly out;
    //     the eye lands on the highlighted track instead.
    if (entryType === "visit") {
      // Match by visit id rather than by ISO `started_at` range — the
      // API returns timestamps with milliseconds (`...:00.000Z`) while
      // DayAssembler renders the row attribute with second precision
      // (`...:00Z`). Lexicographic comparison fails the equality check
      // and dims the hovered visit along with the others.
      const visitExpr = [
        "case",
        ["==", ["get", "id"], Number(visitId)],
        1,
        0.15,
      ]
      this._safeSetPaint("visits", "circle-opacity", visitExpr)
      this._safeSetPaint("visits", "circle-stroke-opacity", visitExpr)
      this.layerManager
        .getLayer("visits")
        ?.setLabelOpacity((f) =>
          f.properties.id === Number(visitId) ? 1 : 0.15,
        )
    } else {
      const VISITS_NEARLY_INVISIBLE = 0.05
      this._safeSetPaint("visits", "circle-opacity", VISITS_NEARLY_INVISIBLE)
      this._safeSetPaint(
        "visits",
        "circle-stroke-opacity",
        VISITS_NEARLY_INVISIBLE,
      )
      this.layerManager
        .getLayer("visits")
        ?.setLabelOpacity(() => VISITS_NEARLY_INVISIBLE)
    }
  }

  /**
   * Handle entry-unhover events — restore to day highlight or default opacity.
   */
  handleEntryUnhover() {
    if (!this.map) return
    this._restoreHighlight()
  }

  /**
   * Handle entry-click events from the timeline feed (journey card opened).
   * Zooms to the track and applies the selection highlight.
   */
  async handleEntryClick(event) {
    const { trackId, startedAt } = event.detail
    if (!this.map) return

    const selectionVersion = this._selectionVersion + 1
    this._selectionVersion = selectionVersion
    let feature = this._findTrackFeature(trackId, startedAt)
    if (!feature && trackId) {
      try {
        feature = await this.api.fetchTrackWithSegments(trackId, {
          ...this.layerManager?.pointTileRange,
        })
      } catch (error) {
        console.warn(`[Map] Failed to load timeline track ${trackId}:`, error)
        return
      }
    }
    if (selectionVersion !== this._selectionVersion) return
    if (!feature) return

    // Zoom to track bounding box
    const geometry = feature.geometry
    const coords =
      geometry?.type === "MultiLineString"
        ? geometry.coordinates.flat()
        : geometry?.coordinates
    if (coords?.length > 0) {
      let minLng = Infinity
      let minLat = Infinity
      let maxLng = -Infinity
      let maxLat = -Infinity
      for (const [lng, lat] of coords) {
        if (lng < minLng) minLng = lng
        if (lat < minLat) minLat = lat
        if (lng > maxLng) maxLng = lng
        if (lat > maxLat) maxLat = lat
      }
      this.map.fitBounds(
        [
          [minLng, minLat],
          [maxLng, maxLat],
        ],
        { padding: 60, maxZoom: 15, duration: 800 },
      )
    }

    // Apply track selection highlight
    const tracksLayer = this.layerManager.getLayer("tracks")
    if (tracksLayer?.setSelectedTrack) {
      const preserveSegments =
        tracksLayer.segmentsActive === true &&
        String(tracksLayer.selectedFeature?.properties?.id) === String(trackId)
      tracksLayer.setSelectedTrack(feature, { preserveSegments })
    }
  }

  /**
   * Handle entry-deselect events from the timeline feed (journey card closed).
   * Clears track selection and restores day highlight if active.
   */
  handleEntryDeselect() {
    if (!this.map) return
    this._selectionVersion = this._selectionVersion + 1

    const tracksLayer = this.layerManager.getLayer("tracks")
    if (tracksLayer?.setSelectedTrack) {
      tracksLayer.setSelectedTrack(null)
    }

    this._restoreHighlight()
  }

  _restoreHighlight() {
    if (this.highlightedDay) {
      this.applyDayHighlight(this.highlightedDay)
    } else {
      this.clearDayHighlight()
    }
  }

  /**
   * Dim tile-backed tracks and points outside the window (Unix seconds).
   * @private
   */
  _dimTracksAndPoints(startUnix, endUnix, dim) {
    this._safeSetPaint(
      "tracks-mvt",
      "line-opacity",
      timeOverlapOpacityExpr(
        "start_timestamp",
        "end_timestamp",
        startUnix,
        endUnix,
        1,
        dim,
      ),
    )
    const pointExpr = timeOverlapOpacityExpr(
      "timestamp",
      "max_timestamp",
      startUnix,
      endUnix,
      1,
      dim,
    )
    this._safeSetPaint("points-mvt", "circle-opacity", pointExpr)
    this._safeSetPaint("points-mvt", "circle-stroke-opacity", pointExpr)
  }

  /**
   * Build a MapLibre expression: full opacity if property is within [start, end], dim otherwise.
   * @private
   */
  _dayRangeExpr(property, rangeStart, rangeEnd, fullOpacity, dimOpacity) {
    return [
      "case",
      [
        "all",
        ["has", property],
        [">=", ["get", property], rangeStart],
        ["<=", ["get", property], rangeEnd],
      ],
      fullOpacity,
      dimOpacity,
    ]
  }

  /**
   * Safely set a paint property on a MapLibre layer (no-op if layer doesn't exist).
   * @private
   */
  _safeSetPaint(layerId, property, value) {
    if (
      layerId === "points-mvt" &&
      ["circle-opacity", "circle-stroke-opacity"].includes(property)
    ) {
      const pointsLayer = this.layerManager?.getLayer("points-mvt")
      if (pointsLayer?.setCircleOpacity) {
        pointsLayer.setCircleOpacity(property, value)
        return
      }
    }
    if (this.map.getLayer(layerId)) {
      this.map.setPaintProperty(layerId, property, value)
    }
  }

  /**
   * Show visit markers for the given day, even if the Visits layer is globally disabled.
   * @param {string} day - Date string "YYYY-MM-DD"
   * @private
   */
  async _showDayVisits(day) {
    const visitsLayer = this.layerManager?.getLayer("visits")
    if (!visitsLayer) return

    const wasHidden = !visitsLayer.visible

    // Get visits for this day
    let dayVisits = []
    if (this.filterManager?.allVisits?.length > 0) {
      dayVisits = this.filterManager.allVisits.filter((v) => {
        const visitDay = v.started_at?.substring(0, 10)
        return visitDay === day
      })
    } else {
      try {
        dayVisits = await this.api.fetchVisits({
          start_at: `${day}T00:00:00`,
          end_at: `${day}T23:59:59`,
        })
      } catch {
        return
      }
    }

    if (dayVisits.length === 0) return

    // Store override state for restoration (only on first override)
    if (!this._visitsOverride) {
      this._visitsOverride = {
        wasHidden,
        previousData: visitsLayer.data || {
          type: "FeatureCollection",
          features: [],
        },
      }
    }

    // Update the visits source with the day's visits and show the layer
    const geoJSON = this.dataLoader.visitsToGeoJSON(dayVisits)
    visitsLayer.update(geoJSON)
    visitsLayer.show()
  }

  /**
   * Restore the visits layer to its previous state after day collapse.
   * @private
   */
  _hideDayVisits() {
    if (!this._visitsOverride) return

    const visitsLayer = this.layerManager?.getLayer("visits")
    if (!visitsLayer) {
      this._visitsOverride = null
      return
    }

    if (this._visitsOverride.wasHidden) {
      visitsLayer.update(this._visitsOverride.previousData)
      visitsLayer.hide()
    }

    this._visitsOverride = null
  }

  /**
   * Find a track feature from the tracks source by ID or start time.
   * @param {string} trackId - Track ID (primary match)
   * @param {string} startedAt - ISO start time (fallback match)
   * @returns {Object|null} GeoJSON feature or null
   * @private
   */
  _findTrackFeature(trackId, startedAt) {
    const tracksLayer = this.layerManager?.getLayer("tracks")
    if (!tracksLayer) return null

    const selected = tracksLayer.selectedFeature
    if (
      selected &&
      !selected.sourceLayer &&
      ((trackId && String(selected.properties?.id) === String(trackId)) ||
        (startedAt && selected.properties?.start_at === startedAt))
    ) {
      return selected
    }

    const sourceData = tracksLayer.data
    if (!sourceData?.features) return null

    // Primary: match by track ID
    if (trackId) {
      const byId = sourceData.features.find(
        (f) => String(f.properties?.id) === String(trackId),
      )
      if (byId) return byId
    }

    // Fallback: match by start_at time
    if (startedAt) {
      return (
        sourceData.features.find((f) => f.properties?.start_at === startedAt) ||
        null
      )
    }

    return null
  }
}
