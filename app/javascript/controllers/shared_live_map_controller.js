import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { translate } from "i18n"
import maplibregl from "maplibre-gl"
import { RecentPointLayer } from "maps_maplibre/layers/recent_point_layer"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    linkId: String,
    showRoute: Boolean,
  }

  static targets = ["map", "status", "lastSeen"]

  connect() {
    this.initializeMap()
  }

  async initializeMap() {
    const style = await getMapStyle("light")

    this.map = new maplibregl.Map({
      container: this.mapTarget,
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
      this.recentLayer = new RecentPointLayer(this.map)
      this.recentLayer.add()
      if (this.showRouteValue) this.initRoute()
      this.loadInitialPoint()
      this.subscribe()
    })
  }

  disconnect() {
    this.stopRelativeTicker()
    if (this.markerRAF) {
      cancelAnimationFrame(this.markerRAF)
      this.markerRAF = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async loadInitialPoint() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/points`)
    if (!res.ok) return
    const points = await res.json()
    if (!points.length) {
      this.setStatus(translate("live_share.location_unknown"))
      return
    }
    const [lon, lat, ts] = points[0]
    this.setStatus("")
    this.placeMarker(lon, lat, ts)
    this.setLastSeen(ts)
  }

  subscribe() {
    this.consumer = createConsumer(
      `/cable?share_id=${encodeURIComponent(this.linkIdValue)}`,
    )
    this.subscription = this.consumer.subscriptions.create(
      { channel: "SharedLocationChannel", share_id: this.linkIdValue },
      {
        received: (data) => this.handleMessage(data),
      },
    )
  }

  handleMessage(data) {
    if (data.revoked) {
      this.setStatus(translate("live_share.ended"))
      this.hideMarker()
      if (this.subscription) this.subscription.unsubscribe()
      return
    }
    if (data.masked) {
      this.setStatus(translate("live_share.location_hidden"))
      this.hideMarker()
      return
    }
    if (data.lon != null && data.lat != null) {
      this.setStatus("")
      this.placeMarker(data.lon, data.lat, data.ts)
      this.setLastSeen(data.ts)
      if (this.showRouteValue) this.appendToRoute(data.lon, data.lat)
    }
  }

  async initRoute() {
    this.routeCoords = []
    this.map.addSource("live-route-source", {
      type: "geojson",
      data: this.routeFeature(),
    })
    this.map.addLayer(
      {
        id: "live-route",
        type: "line",
        source: "live-route-source",
        layout: { "line-join": "round", "line-cap": "round" },
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.8,
        },
      },
      "recent-point-pulse",
    )
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/route`)
    if (!res.ok) return
    const points = await res.json()
    this.routeCoords = points.map(([lon, lat]) => [lon, lat])
    this.renderRoute()
  }

  appendToRoute(lon, lat) {
    if (!this.routeCoords) return
    const last = this.routeCoords[this.routeCoords.length - 1]
    if (last && last[0] === lon && last[1] === lat) return
    this.routeCoords.push([lon, lat])
    this.renderRoute()
  }

  renderRoute() {
    const src = this.map.getSource("live-route-source")
    if (src) src.setData(this.routeFeature())
  }

  routeFeature() {
    return {
      type: "Feature",
      geometry: { type: "LineString", coordinates: this.routeCoords || [] },
    }
  }

  placeMarker(lon, lat, ts) {
    this.updateTimeLabel(lon, lat, ts)
    this.animateMarkerTo(lon, lat)
    this.map.easeTo({
      center: [lon, lat],
      zoom: Math.max(this.map.getZoom(), 13),
      duration: this.markerAnimDuration,
      easing: (t) => t,
    })
  }

  animateMarkerTo(lon, lat) {
    const now = performance.now()
    const interval = this.lastMarkerUpdate ? now - this.lastMarkerUpdate : 0
    this.lastMarkerUpdate = now
    this.markerAnimDuration =
      interval > 0 ? Math.min(2500, Math.max(300, interval)) : 0
    this.markerAnim = {
      from: this.markerPos || [lon, lat],
      to: [lon, lat],
      start: now,
      duration: this.markerAnimDuration,
    }
    if (!this.markerRAF) this.tickMarker()
  }

  tickMarker() {
    const anim = this.markerAnim
    if (!anim) {
      this.markerRAF = null
      return
    }
    const t =
      anim.duration > 0
        ? Math.min(1, (performance.now() - anim.start) / anim.duration)
        : 1
    const lon = anim.from[0] + (anim.to[0] - anim.from[0]) * t
    const lat = anim.from[1] + (anim.to[1] - anim.from[1]) * t
    this.markerPos = [lon, lat]
    if (this.recentLayer) this.recentLayer.updateRecentPoint(lon, lat)
    if (this.timeLabel) this.timeLabel.setLngLat([lon, lat])
    if (t < 1) {
      this.markerRAF = requestAnimationFrame(() => this.tickMarker())
    } else {
      this.markerPos = anim.to
      this.markerAnim = null
      this.markerRAF = null
    }
  }

  updateTimeLabel(lon, lat, ts) {
    if (ts == null) return
    const label = new Date(Number(ts) * 1000).toLocaleTimeString()
    if (!this.timeLabel) {
      const el = document.createElement("div")
      el.style.cssText =
        "padding:2px 6px;border-radius:6px;background:rgba(255,255,255,0.9);color:#1f2937;font-size:12px;font-weight:600;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,0.25);pointer-events:none;"
      this.timeLabel = new maplibregl.Marker({
        element: el,
        anchor: "top",
        offset: [0, 16],
      })
        .setLngLat(this.markerPos || [lon, lat])
        .addTo(this.map)
    }
    this.timeLabel.getElement().textContent = label
  }

  hideMarker() {
    if (this.recentLayer) this.recentLayer.clear()
    if (this.timeLabel) {
      this.timeLabel.remove()
      this.timeLabel = null
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  setLastSeen(ts) {
    if (!this.hasLastSeenTarget) return
    if (ts == null) {
      this.lastSeenTarget.textContent = ""
      this.lastSeenTs = null
      this.stopRelativeTicker()
      return
    }
    this.lastSeenTs = Number(ts)
    this.renderLastSeen()
    this.startRelativeTicker()
  }

  renderLastSeen() {
    if (!this.hasLastSeenTarget || this.lastSeenTs == null) return
    const seenAt = new Date(this.lastSeenTs * 1000)
    this.lastSeenTarget.textContent = translate("live_share.last_seen", {
      date: seenAt.toLocaleString(document.documentElement.lang || undefined),
      relative: this.relativeTime(this.lastSeenTs),
    })
  }

  relativeTime(ts) {
    const diff = Math.floor(Date.now() / 1000) - Number(ts)
    const rtf = new Intl.RelativeTimeFormat(
      document.documentElement.lang || undefined,
      { numeric: "always" },
    )
    if (diff < 60) return rtf.format(-diff, "second")
    if (diff < 3600) return rtf.format(-Math.floor(diff / 60), "minute")
    if (diff < 86400) return rtf.format(-Math.floor(diff / 3600), "hour")
    return rtf.format(-Math.floor(diff / 86400), "day")
  }

  startRelativeTicker() {
    if (this.relativeTicker) return
    this.relativeTicker = setInterval(() => this.renderLastSeen(), 1000)
  }

  stopRelativeTicker() {
    if (this.relativeTicker) {
      clearInterval(this.relativeTicker)
      this.relativeTicker = null
    }
  }
}
