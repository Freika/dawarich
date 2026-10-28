import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { generateDayPalette } from "../utils/day_route_collections"

const SOURCE_ID = "trip-routes"
const LAYER_ID = "trip-routes-layer"
const SOURCE_LAYER = "trip_routes"
const FALLBACK_COLOR = "#6366F1"
const MAX_EXCLUDED_WINDOWS = 50

export class TripRoutesTileLayer {
  constructor(
    map,
    {
      tilesUrl,
      dayKeys = [],
      dayBounds = {},
      fullBounds = null,
      dayEndpoints = {},
    },
  ) {
    this.map = map
    this.tilesUrl = tilesUrl
    this.dayKeys = [...dayKeys].sort()
    const palette = generateDayPalette(this.dayKeys.length)
    this.dayColors = new Map(
      this.dayKeys.map((day, index) => [day, palette[index]]),
    )
    this.dayBounds = dayBounds
    this.fullBounds = fullBounds
    this.dayEndpoints = dayEndpoints
    this.excludedWindows = []
    this.selectedDay = null
    this.hoveredDay = null
    this.interactionHandlers = []
    this.hoverMarkers = []
    this.add()
  }

  add() {
    this.map.addSource(SOURCE_ID, {
      type: "vector",
      tiles: [this.tileUrl()],
      minzoom: 0,
      maxzoom: 22,
    })
    this.map.addLayer({
      id: LAYER_ID,
      type: "line",
      source: SOURCE_ID,
      "source-layer": SOURCE_LAYER,
      layout: { "line-join": "round", "line-cap": "round" },
      paint: {
        "line-color": this.colorExpression(),
        "line-width": 3,
        "line-opacity": 0.9,
      },
    })
  }

  colorExpression() {
    if (this.dayColors.size === 0) return FALLBACK_COLOR

    return [
      "match",
      ["get", "day"],
      ...[...this.dayColors].flat(),
      FALLBACK_COLOR,
    ]
  }

  tileUrl() {
    if (this.excludedWindows.length === 0) return this.tilesUrl

    const separator = this.tilesUrl.includes("?") ? "&" : "?"
    const windows = this.excludedWindows.map(([from, to]) => `${from}-${to}`)
    return `${this.tilesUrl}${separator}exclude=${windows.join(",")}`
  }

  setExcludedWindows(windows) {
    const normalized = []
    for (const [from, to] of (windows || [])
      .map(([from, to]) => [
        Math.floor(from),
        Math.max(Math.ceil(to), Math.floor(from) + 1),
      ])
      .sort((a, b) => a[0] - b[0])) {
      const last = normalized.at(-1)
      if (last && from <= last[1]) last[1] = Math.max(last[1], to)
      else normalized.push([from, to])
    }
    normalized.splice(MAX_EXCLUDED_WINDOWS)
    if (JSON.stringify(normalized) === JSON.stringify(this.excludedWindows))
      return

    this.excludedWindows = normalized
    this.map.getSource(SOURCE_ID)?.setTiles([this.tileUrl()])
  }

  emphasise(day, width) {
    if (!this.map.getLayer(LAYER_ID)) return

    const isDay = ["==", ["get", "day"], day]
    this.map.setPaintProperty(LAYER_ID, "line-opacity", [
      "case",
      isDay,
      1,
      0.25,
    ])
    this.map.setPaintProperty(LAYER_ID, "line-width", ["case", isDay, width, 2])
  }

  selectDay(day) {
    this.selectedDay = day
    this.emphasise(day, 4)
  }

  selectAllDays() {
    this.selectedDay = null
    if (!this.map.getLayer(LAYER_ID)) return

    this.map.setPaintProperty(LAYER_ID, "line-opacity", 0.9)
    this.map.setPaintProperty(LAYER_ID, "line-width", 3)
  }

  restoreSelection() {
    if (this.selectedDay) {
      this.selectDay(this.selectedDay)
    } else {
      this.selectAllDays()
    }
  }

  getDayColor(day) {
    return this.dayColors.get(day) || null
  }

  getDayKeys() {
    return this.dayKeys
  }

  getDayBounds(day) {
    return this.toBounds(this.dayBounds[day])
  }

  getFullBounds() {
    return this.toBounds(this.fullBounds)
  }

  toBounds(pair) {
    return pair?.length === 2
      ? new maplibregl.LngLatBounds(pair[0], pair[1])
      : null
  }

  setupInteractions({ onDayClick } = {}) {
    const click = (event) => {
      const day = event.features?.[0]?.properties?.day
      if (day && onDayClick) onDayClick(day)
    }
    const move = (event) => {
      const day = event.features?.[0]?.properties?.day
      if (!day || day === this.hoveredDay) return

      this.hoveredDay = day
      this.map.getCanvas().style.cursor = "pointer"
      this.emphasise(day, 5)
      this.showEndpoints(day)
    }
    const leave = () => {
      this.hoveredDay = null
      this.map.getCanvas().style.cursor = ""
      this.removeHoverMarkers()
      this.restoreSelection()
    }

    for (const [type, handler] of [
      ["click", click],
      ["mousemove", move],
      ["mouseleave", leave],
    ]) {
      this.map.on(type, LAYER_ID, handler)
      this.interactionHandlers.push({ type, handler })
    }
  }

  showEndpoints(day) {
    this.removeHoverMarkers()
    const endpoints = this.dayEndpoints[day]
    if (!endpoints?.first || !endpoints?.last) return

    this.hoverMarkers = [
      this.createCircleMarker(
        endpoints.first,
        "#22c55e",
        translate("map_info.start"),
      ),
      this.createCircleMarker(
        endpoints.last,
        "#ef4444",
        translate("map_info.end"),
      ),
    ]
  }

  createCircleMarker(lngLat, color, label) {
    const element = document.createElement("div")
    element.style.cssText = `
      width: 10px; height: 10px; border-radius: 50%;
      background: ${color}; border: 2px solid white;
      box-shadow: 0 1px 3px rgba(0,0,0,0.4);
    `
    element.title = label

    return new maplibregl.Marker({ element }).setLngLat(lngLat).addTo(this.map)
  }

  removeHoverMarkers() {
    for (const marker of this.hoverMarkers) marker.remove()
    this.hoverMarkers = []
  }

  removeInteractions() {
    for (const { type, handler } of this.interactionHandlers) {
      this.map.off(type, LAYER_ID, handler)
    }
    this.interactionHandlers = []
    this.removeHoverMarkers()
    this.hoveredDay = null
  }

  remove() {
    this.removeInteractions()
    if (this.map.getLayer(LAYER_ID)) this.map.removeLayer(LAYER_ID)
    if (this.map.getSource(SOURCE_ID)) this.map.removeSource(SOURCE_ID)
  }
}
