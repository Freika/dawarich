import maplibregl from "maplibre-gl"
import { RouteSegmenter } from "../utils/route_segmenter"

/**
 * DayRoutesLayer - Manages day-colored route layers for trips
 * Each day gets its own source/layer with a distinct HSL color.
 * Supports highlight/dim for day selection.
 */
export class DayRoutesLayer {
  constructor(map) {
    this.map = map
    this.daySources = new Map() // dayKey -> sourceId
    this.dayLayers = new Map() // dayKey -> layerId
    this.dayColors = new Map() // dayKey -> color string
    this.dayBounds = new Map() // dayKey -> LngLatBounds
    this.fullBounds = null
    this.selectedDay = null
  }

  /**
   * Generate N distinct colors using HSL rotation
   * @param {number} numDays - Number of days
   * @returns {string[]} Array of HSL color strings
   */
  static generateDayPalette(numDays) {
    // Curated palette: perceptually distinct, high contrast on map tiles
    const PALETTE = [
      "#6366F1", // Indigo
      "#F43F5E", // Rose
      "#10B981", // Emerald
      "#F59E0B", // Amber
      "#0EA5E9", // Sky
      "#A855F7", // Purple
      "#F97316", // Orange
      "#14B8A6", // Teal
      "#EC4899", // Pink
      "#84CC16", // Lime
      "#06B6D4", // Cyan
      "#D946EF", // Fuchsia
    ]

    if (numDays === 1) return [PALETTE[0]]
    if (numDays <= PALETTE.length) return PALETTE.slice(0, numDays)

    // Fall back to HSL rotation for trips > 12 days
    return Array.from({ length: numDays }, (_, i) => {
      const hue = (i * (360 / numDays)) % 360
      return `hsl(${hue}, 70%, 55%)`
    })
  }

  /**
   * Build and add day-colored routes to the map
   * @param {Object} pointsByDay - { 'YYYY-MM-DD': [points...] }
   * @param {Object} options - Route segmenter options
   */
  addDayRoutes(pointsByDay, options = {}) {
    const dayKeys = Object.keys(pointsByDay).sort()
    const colors = DayRoutesLayer.generateDayPalette(dayKeys.length)
    const allCoords = []

    dayKeys.forEach((dayKey, i) => {
      const points = pointsByDay[dayKey]
      if (points.length < 2) return

      const color = colors[i]
      this.dayColors.set(dayKey, color)

      // Use RouteSegmenter to build route GeoJSON for this day
      const routeGeoJSON = RouteSegmenter.pointsToRoutes(points, {
        distanceThresholdMeters: options.distanceThresholdMeters || 500,
        timeThresholdMinutes: options.timeThresholdMinutes || 60,
      })

      // Set color on each feature
      for (const feature of routeGeoJSON.features) {
        feature.properties.color = color
        feature.properties.dayKey = dayKey
      }

      const sourceId = `day-route-${dayKey}`
      const layerId = `day-route-layer-${dayKey}`

      this.daySources.set(dayKey, sourceId)
      this.dayLayers.set(dayKey, layerId)

      // Add source
      if (!this.map.getSource(sourceId)) {
        this.map.addSource(sourceId, {
          type: "geojson",
          data: routeGeoJSON,
        })
      }

      // Add layer
      if (!this.map.getLayer(layerId)) {
        this.map.addLayer({
          id: layerId,
          type: "line",
          source: sourceId,
          layout: {
            "line-join": "round",
            "line-cap": "round",
          },
          paint: {
            "line-color": color,
            "line-width": 3,
            "line-opacity": 0.9,
          },
        })
      }

      // Calculate bounds for this day
      const dayBounds = new maplibregl.LngLatBounds()
      for (const feature of routeGeoJSON.features) {
        for (const coord of feature.geometry.coordinates) {
          dayBounds.extend(coord)
        }
      }
      if (!dayBounds.isEmpty()) {
        this.dayBounds.set(dayKey, dayBounds)
      }

      // Collect all coords for full bounds
      for (const feature of routeGeoJSON.features) {
        for (const coord of feature.geometry.coordinates) {
          allCoords.push(coord)
        }
      }
    })

    // Calculate full trip bounds
    if (allCoords.length > 0) {
      this.fullBounds = new maplibregl.LngLatBounds()
      for (const coord of allCoords) {
        this.fullBounds.extend(coord)
      }
    }
  }

  /**
   * Highlight a specific day's route and dim others
   * @param {string} dayKey - Day key like '2025-01-15'
   */
  selectDay(dayKey) {
    this.selectedDay = dayKey

    for (const [key, layerId] of this.dayLayers) {
      if (!this.map.getLayer(layerId)) continue

      if (key === dayKey) {
        this.map.setPaintProperty(layerId, "line-opacity", 1.0)
        this.map.setPaintProperty(layerId, "line-width", 4)
      } else {
        this.map.setPaintProperty(layerId, "line-opacity", 0.25)
        this.map.setPaintProperty(layerId, "line-width", 2)
      }
    }
  }

  /**
   * Show all days at normal opacity
   */
  selectAllDays() {
    this.selectedDay = null

    for (const [, layerId] of this.dayLayers) {
      if (!this.map.getLayer(layerId)) continue
      this.map.setPaintProperty(layerId, "line-opacity", 0.9)
      this.map.setPaintProperty(layerId, "line-width", 3)
    }
  }

  /**
   * Get bounds for a specific day
   * @param {string} dayKey
   * @returns {maplibregl.LngLatBounds|null}
   */
  getDayBounds(dayKey) {
    return this.dayBounds.get(dayKey) || null
  }

  /**
   * Get bounds for the full trip
   * @returns {maplibregl.LngLatBounds|null}
   */
  getFullBounds() {
    return this.fullBounds
  }

  /**
   * Get color for a specific day
   * @param {string} dayKey
   * @returns {string|null}
   */
  getDayColor(dayKey) {
    return this.dayColors.get(dayKey) || null
  }

  /**
   * Get all day keys that have routes
   * @returns {string[]}
   */
  getDayKeys() {
    return Array.from(this.dayLayers.keys()).sort()
  }

  /**
   * Register click and hover interactions on all day layers
   * @param {Object} callbacks - { onDayClick: (dayKey) => void }
   */
  setupInteractions(callbacks) {
    this.interactionHandlers = []
    this.hoverMarkers = []
    this.hoveredDayKey = null

    for (const [dayKey, layerId] of this.dayLayers) {
      const clickHandler = (e) => {
        const feature = e.features?.[0]
        if (!feature) return
        const key = feature.properties.dayKey
        if (key && callbacks.onDayClick) {
          callbacks.onDayClick(key)
        }
      }

      const mouseEnterHandler = (e) => {
        const feature = e.features?.[0]
        if (!feature) return

        this.map.getCanvas().style.cursor = "pointer"
        this.hoveredDayKey = dayKey

        // Highlight hovered day, dim others
        for (const [key, lid] of this.dayLayers) {
          if (!this.map.getLayer(lid)) continue
          if (key === dayKey) {
            this.map.setPaintProperty(lid, "line-opacity", 1.0)
            this.map.setPaintProperty(lid, "line-width", 5)
          } else {
            this.map.setPaintProperty(lid, "line-opacity", 0.25)
            this.map.setPaintProperty(lid, "line-width", 2)
          }
        }

        // Add start/end markers for the hovered segment
        this.removeHoverMarkers()
        const coords = feature.geometry.coordinates
        if (coords && coords.length >= 2) {
          const startCoord = coords[0]
          const endCoord = coords[coords.length - 1]

          this.hoverMarkers.push(
            this.createCircleMarker(startCoord, "#22c55e", "Start"),
          )
          this.hoverMarkers.push(
            this.createCircleMarker(endCoord, "#ef4444", "End"),
          )
        }
      }

      const mouseLeaveHandler = () => {
        this.map.getCanvas().style.cursor = ""
        this.hoveredDayKey = null
        this.removeHoverMarkers()

        // Restore paint state
        if (this.selectedDay) {
          this.selectDay(this.selectedDay)
        } else {
          this.selectAllDays()
        }
      }

      this.map.on("click", layerId, clickHandler)
      this.map.on("mouseenter", layerId, mouseEnterHandler)
      this.map.on("mouseleave", layerId, mouseLeaveHandler)

      this.interactionHandlers.push(
        { type: "click", layerId, handler: clickHandler },
        { type: "mouseenter", layerId, handler: mouseEnterHandler },
        { type: "mouseleave", layerId, handler: mouseLeaveHandler },
      )
    }
  }

  /**
   * Create a small circle marker with a label
   * @param {number[]} lngLat - [lng, lat]
   * @param {string} color - CSS color
   * @param {string} label - "Start" or "End"
   * @returns {maplibregl.Marker}
   */
  createCircleMarker(lngLat, color, label) {
    const el = document.createElement("div")
    el.style.cssText = `
      width: 10px; height: 10px; border-radius: 50%;
      background: ${color}; border: 2px solid white;
      box-shadow: 0 1px 3px rgba(0,0,0,0.4);
    `
    el.title = label

    return new maplibregl.Marker({ element: el })
      .setLngLat(lngLat)
      .addTo(this.map)
  }

  /**
   * Remove hover markers from the map
   */
  removeHoverMarkers() {
    for (const marker of this.hoverMarkers) {
      marker.remove()
    }
    this.hoverMarkers = []
  }

  /**
   * Remove all interaction event listeners
   */
  removeInteractions() {
    if (this.interactionHandlers) {
      for (const { type, layerId, handler } of this.interactionHandlers) {
        this.map.off(type, layerId, handler)
      }
      this.interactionHandlers = []
    }
    this.removeHoverMarkers()
    this.hoveredDayKey = null
  }

  /**
   * Remove all day route layers and sources
   */
  remove() {
    this.removeInteractions()
    for (const [, layerId] of this.dayLayers) {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    }

    for (const [, sourceId] of this.daySources) {
      if (this.map.getSource(sourceId)) {
        this.map.removeSource(sourceId)
      }
    }

    this.daySources.clear()
    this.dayLayers.clear()
    this.dayColors.clear()
    this.dayBounds.clear()
    this.fullBounds = null
    this.selectedDay = null
  }
}
