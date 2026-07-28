import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { DayRoutesLayer } from "maps_maplibre/layers/day_routes_layer"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    linkId: String,
    showPhotos: Boolean,
    byDay: Boolean,
    timezone: String,
  }

  static targets = [
    "map",
    "replayToggleBtn",
    "replayPanel",
    "replayScrubber",
    "replayScrubberTrack",
    "replayDensityContainer",
    "replayDayDisplay",
    "replayDayCount",
    "replayPrevDayButton",
    "replayNextDayButton",
    "replayTimeDisplay",
    "replaySpeedDisplay",
    "replayDataIndicator",
    "replayPlayButton",
    "replayFollowButton",
    "replayPlayIcon",
    "replayPauseIcon",
    "replaySpeedSlider",
    "replaySpeedLabel",
    "replayCycleControls",
    "replayPointCounter",
  ]

  connect() {
    this.selectedDay = null
    this.allPoints = []
    this.photoMarkers = []
    this.initializeMap()
  }

  get mapContainer() {
    return this.hasMapTarget ? this.mapTarget : this.element
  }

  async initializeMap() {
    const style = await getMapStyle("light")

    this.map = new maplibregl.Map({
      container: this.mapContainer,
      style,
      center: [0, 0],
      zoom: 1,
      attributionControl: { compact: true },
      interactive: true,
    })

    this.map.addControl(
      new maplibregl.NavigationControl({ showCompass: false }),
      "top-right",
    )

    this.map.on("load", () => {
      if (this.byDayValue) {
        this.loadDayRoutes()
      } else {
        this.loadPoints()
      }
      if (this.showPhotosValue) this.loadPhotos()
    })
  }

  disconnect() {
    if (this.replayPanel) {
      this.replayPanel.destroy()
      this.replayPanel = null
    }
    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.remove()
      this.dayRoutesLayer = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async fetchPoints() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/points`)
    if (!res.ok) return []
    return res.json()
  }

  async loadPoints() {
    const points = await this.fetchPoints()
    if (!points.length) return

    const coords = points.map(([lon, lat]) => [lon, lat])

    this.map.addSource("route", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: { type: "LineString", coordinates: coords },
      },
    })
    this.map.addLayer({
      id: "route-line",
      type: "line",
      source: "route",
      paint: { "line-color": "#6366F1", "line-width": 3 },
    })

    const bounds = coords.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coords[0], coords[0]),
    )
    this.map.fitBounds(bounds, { padding: 40, duration: 0 })
  }

  async loadDayRoutes() {
    const points = await this.fetchPoints()
    if (!points.length) return

    this.allPoints = points.map(([lon, lat, ts]) => ({
      longitude: lon,
      latitude: lat,
      timestamp: ts,
    }))

    const pointsByDay = this.groupByDay(points)

    this.dayRoutesLayer = new DayRoutesLayer(this.map)
    this.dayRoutesLayer.addDayRoutes(pointsByDay)
    this.recolorDots()
    this.dayRoutesLayer.setupInteractions({
      onDayClick: (dayKey) => this.pinDay(dayKey),
    })

    const bounds = this.dayRoutesLayer.getFullBounds()
    if (bounds)
      this.map.fitBounds(bounds, { padding: 40, maxZoom: 15, duration: 0 })
  }

  groupByDay(points) {
    const fmt = this.dayFormatter()
    const byDay = {}
    for (const [lon, lat, ts] of points) {
      const key = fmt.format(new Date(ts * 1000))
      if (!byDay[key]) byDay[key] = []
      byDay[key].push({ longitude: lon, latitude: lat, timestamp: ts })
    }
    return byDay
  }

  dayFormatter() {
    const opts = { year: "numeric", month: "2-digit", day: "2-digit" }
    try {
      return new Intl.DateTimeFormat("en-CA", {
        timeZone: this.timezoneValue || "UTC",
        ...opts,
      })
    } catch {
      return new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", ...opts })
    }
  }

  recolorDots() {
    for (const dot of this.element.querySelectorAll("[data-day-dot]")) {
      const color = this.dayRoutesLayer.getDayColor(dot.dataset.dayDot)
      if (color) dot.style.backgroundColor = color
    }
  }

  // ----- right-panel row interactions -----

  hoverDay(event) {
    const dayKey = event.params.dayKey
    if (!this.dayRoutesLayer?.getDayColor(dayKey)) return
    this.dayRoutesLayer.selectDay(dayKey)
  }

  leaveDay() {
    if (!this.dayRoutesLayer) return
    if (this.selectedDay) {
      this.dayRoutesLayer.selectDay(this.selectedDay)
    } else {
      this.dayRoutesLayer.selectAllDays()
    }
  }

  toggleDay(event) {
    this.pinDay(event.params.dayKey)
  }

  pinDay(dayKey) {
    if (!this.dayRoutesLayer?.getDayColor(dayKey)) return

    if (this.selectedDay === dayKey) {
      this.selectedDay = null
      this.dayRoutesLayer.selectAllDays()
      const full = this.dayRoutesLayer.getFullBounds()
      if (full) this.map.fitBounds(full, { padding: 40, maxZoom: 15 })
    } else {
      this.selectedDay = dayKey
      this.dayRoutesLayer.selectDay(dayKey)
      const dayBounds = this.dayRoutesLayer.getDayBounds(dayKey)
      if (dayBounds) this.map.fitBounds(dayBounds, { padding: 60, maxZoom: 15 })
    }
    this.markActiveRow()
    this.replayPanel?.syncToDay(dayKey)
  }

  // ----- replay (delegates to the reusable ReplayPanel) -----

  toggleReplay() {
    if (!this.replayPanel) {
      this.replayPanel = new ReplayPanel({
        controller: this,
        map: this.map,
        dayRoutesLayer: this.dayRoutesLayer,
        element: this.element,
        timezone: this.timezoneValue,
        allPoints: this.allPoints,
        getPhotos: () =>
          (this.photoMarkers || []).map(({ photo }) => ({
            id: photo.id,
            taken_at: photo.taken_at,
            thumbnail_url: photo.thumbnail_url,
            latitude: photo.latitude,
            longitude: photo.longitude,
            source: photo.source,
          })),
        onReplayPhotosActive: (active) => {
          for (const { marker } of this.photoMarkers || []) {
            marker.getElement().style.display = active ? "none" : ""
          }
        },
      })
    }
    this.replayPanel.toggle()
  }

  replayScrubberHover(event) {
    this.replayPanel?.scrubberHover(event)
  }

  replayPrevDay() {
    this.replayPanel?.prevDay()
  }

  replayNextDay() {
    this.replayPanel?.nextDay()
  }

  replayCyclePrev() {
    this.replayPanel?.cyclePrev()
  }

  replayCycleNext() {
    this.replayPanel?.cycleNext()
  }

  replayTogglePlayback() {
    this.replayPanel?.togglePlayback()
  }

  replayRecenterFollow() {
    this.replayPanel?.recenterFollow()
  }

  replaySpeedChange(event) {
    this.replayPanel?.speedChange(event)
  }

  markActiveRow() {
    for (const row of this.element.querySelectorAll("[data-day-key]")) {
      row.classList.toggle("ring-2", row.dataset.dayKey === this.selectedDay)
      row.classList.toggle(
        "ring-primary",
        row.dataset.dayKey === this.selectedDay,
      )
    }
  }

  async loadPhotos() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/photos`)
    if (!res.ok) return
    const photos = await res.json()

    this.photoMarkers = []
    for (const photo of photos) {
      if (photo.latitude == null || photo.longitude == null) continue
      const el = document.createElement("img")
      el.src = photo.thumbnail_url
      el.className =
        "shared-photo-marker rounded-full border-2 border-white shadow"
      el.style.width = "32px"
      el.style.height = "32px"
      el.style.objectFit = "cover"
      const marker = new maplibregl.Marker({ element: el })
        .setLngLat([photo.longitude, photo.latitude])
        .addTo(this.map)
      this.photoMarkers.push({ photo, marker })
    }
  }
}
