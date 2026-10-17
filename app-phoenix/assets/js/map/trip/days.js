import { maskLines } from "../algorithms/flight_mask.js"
import { RouteSegmenter } from "../algorithms/route_segmenter.js"
import { DayInteractions } from "./interactions.js"
export class DayRoutesLayer extends DayInteractions {
  constructor(map, options = {}) {
    super(map, options)
    this.map = map
    this.daySources = new Map()
    this.dayLayers = new Map()
    this.dayColors = new Map()
    this.dayRouteData = new Map()
    this.dayBounds = new Map()
    this.fullBounds = null
    this.selectedDay = null
  }
  static generateDayPalette(numDays) {
    const PALETTE = [
      "#6366F1",
      "#F43F5E",
      "#10B981",
      "#F59E0B",
      "#0EA5E9",
      "#A855F7",
      "#F97316",
      "#14B8A6",
      "#EC4899",
      "#84CC16",
      "#06B6D4",
      "#D946EF",
    ]
    if (numDays === 1) return [PALETTE[0]]
    if (numDays <= PALETTE.length) return PALETTE.slice(0, numDays)
    return Array.from({ length: numDays }, (_, i) => {
      const hue = (i * (360 / numDays)) % 360
      return `hsl(${hue}, 70%, 55%)`
    })
  }
  addDayRoutes(pointsByDay, options = {}) {
    const dayKeys = Object.keys(pointsByDay).sort()
    const colors = DayRoutesLayer.generateDayPalette(dayKeys.length)
    const allCoords = []
    dayKeys.forEach((dayKey, i) => {
      const points = pointsByDay[dayKey]
      if (points.length < 2) return
      const color = colors[i]
      this.dayColors.set(dayKey, color)
      const routeGeoJSON = RouteSegmenter.pointsToRoutes(points, {
        distanceThresholdMeters: options.distanceThresholdMeters || 500,
        timeThresholdMinutes: options.timeThresholdMinutes || 60,
      })
      for (const feature of routeGeoJSON.features) {
        feature.properties.color = color
        feature.properties.dayKey = dayKey
      }
      const sourceId = `day-route-${dayKey}`
      const layerId = `day-route-layer-${dayKey}`
      this.daySources.set(dayKey, sourceId)
      this.dayLayers.set(dayKey, layerId)
      this.dayRouteData.set(dayKey, routeGeoJSON)
      if (!this.map.getSource(sourceId)) {
        this.map.addSource(sourceId, {
          type: "geojson",
          data: routeGeoJSON,
        })
      }
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
      const dayBounds = new this.library.LngLatBounds()
      for (const feature of routeGeoJSON.features) {
        for (const coord of feature.geometry.coordinates) {
          dayBounds.extend(coord)
        }
      }
      if (!dayBounds.isEmpty()) {
        this.dayBounds.set(dayKey, dayBounds)
      }
      for (const feature of routeGeoJSON.features) {
        for (const coord of feature.geometry.coordinates) {
          allCoords.push(coord)
        }
      }
    })
    if (allCoords.length > 0) {
      this.fullBounds = new this.library.LngLatBounds()
      for (const coord of allCoords) {
        this.fullBounds.extend(coord)
      }
    }
  }
  maskRoutes(windows) {
    for (const [dayKey, sourceId] of this.daySources) {
      const original = this.dayRouteData.get(dayKey)
      if (!original) continue
      const source = this.map.getSource(sourceId)
      if (!source?.setData) continue
      source.setData(windows?.length ? maskLines(original, windows) : original)
    }
  }
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
  selectAllDays() {
    this.selectedDay = null
    for (const [, layerId] of this.dayLayers) {
      if (!this.map.getLayer(layerId)) continue
      this.map.setPaintProperty(layerId, "line-opacity", 0.9)
      this.map.setPaintProperty(layerId, "line-width", 3)
    }
  }
  getDayBounds(dayKey) {
    return this.dayBounds.get(dayKey) || null
  }
  getFullBounds() {
    return this.fullBounds
  }
  getDayColor(dayKey) {
    return this.dayColors.get(dayKey) || null
  }
  getDayKeys() {
    return Array.from(this.dayLayers.keys()).sort()
  }
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
    this.dayRouteData.clear()
    this.dayBounds.clear()
    this.fullBounds = null
    this.selectedDay = null
  }
}
