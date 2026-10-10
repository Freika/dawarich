import { clearGalleries, openGallery, showGallery } from "./shared_gallery.js"
import { loadSharedMap } from "./shared_map_library.js"
import { photoMarkers } from "./shared_photo_markers.js"
import { PublicReplay } from "./shared_replay.js"
import { publicRoutes } from "./shared_routes.js"

export const SharedMap = {
  mounted() {
    this.generation = 0
    this.points = []
    this.markers = []
    this.listeners = [
      this.handleEvent("public-share-snapshot", (snapshot) =>
        this.show(snapshot),
      ),
      this.handleEvent("public-share-clear", () => this.clear(true)),
    ]
    this.toggle = (event) => {
      if (event.target.matches?.("[data-public-gallery]"))
        openGallery(event.target)
    }
    this.click = (event) => {
      if (event.target.closest?.("[data-public-replay]"))
        this.replayer?.action("toggleReplay")
      const action = event.target.closest?.("[data-public-replay-action]")
      if (action && action.tagName !== "INPUT")
        this.replayer?.action(action.dataset.publicReplayAction)
      const day = event.target.closest?.("[data-public-day]")?.dataset.publicDay
      if (day) this.selectDay(day)
    }
    this.input = (event) => {
      const name = event.target.dataset?.publicReplayAction
      if (name) this.replayer?.action(name, event.target.value)
    }
    this.el.addEventListener("input", this.input)
    this.el.addEventListener("toggle", this.toggle, true)
    this.el.addEventListener("click", this.click)
  },
  async show(snapshot) {
    this.clear(false)
    const generation = this.generation
    const points = snapshot.points || []
    const latest = snapshot.latest || []
    const photos = snapshot.photos || []
    showGallery(this.el, photos, snapshot.zone || "UTC")
    const canvas = this.el.querySelector("[data-public-canvas]")
    const positions = latest.length ? latest : points
    if (!canvas || !positions.length) return
    const controller = new AbortController()
    this.controller = controller
    try {
      const { maplibre, style } = await (this.loader || loadSharedMap)({
        signal: controller.signal,
      })
      if (generation !== this.generation) return
      this.points = points
      this.zone = snapshot.zone || "UTC"
      this.routeOptions = snapshot
      this.library = maplibre
      canvas.hidden = false
      const empty = this.el.querySelector("[data-public-empty]")
      if (empty) empty.hidden = true
      const first = positions[0]
      const map = new maplibre.Map({
        container: canvas,
        style,
        center: first.slice(0, 2),
        zoom: 12,
      })
      this.map = map
      this.replayer = new PublicReplay(
        this.el,
        map,
        maplibre,
        points,
        this.zone,
        this.el.dataset.locale || "en",
      )
      map.addControl(new maplibre.NavigationControl())
      for (const point of latest)
        this.markers.push(
          new maplibre.Marker().setLngLat(point.slice(0, 2)).addTo(map),
        )
      this.markers.push(...photoMarkers(map, maplibre, photos))
      this.latest(latest[0])
      if (positions.length > 1) {
        const xs = positions.map((p) => p[0]),
          ys = positions.map((p) => p[1])
        map.fitBounds(
          [
            [Math.min(...xs), Math.min(...ys)],
            [Math.max(...xs), Math.max(...ys)],
          ],
          { padding: 40, maxZoom: 14 },
        )
      }
      const ready = () => {
        if (generation !== this.generation || this.map !== map) return
        this.route(points)
      }
      if (map.isStyleLoaded()) ready()
      else map.once("load", ready)
    } catch {
      if (generation === this.generation) this.clear(true)
    }
  },
  route(points) {
    if (!this.map) return
    const data = publicRoutes(
      points,
      this.routeOptions || { zone: this.zone || "UTC" },
    )
    const source = this.map.getSource("public-route")
    if (source) source.setData(data)
    else if (points.length > 1) {
      this.map.addSource("public-route", { type: "geojson", data })
      this.map.addLayer({
        id: "public-route",
        type: "line",
        source: "public-route",
        paint: {
          "line-color": ["coalesce", ["get", "color"], "#6366F1"],
          "line-width": 4,
        },
      })
    }
  },
  latest(point) {
    const status = this.el.querySelector("[data-public-status]")
    const seen = this.el.querySelector("[data-public-last-seen]")
    if (status) status.hidden = Boolean(point)
    if (seen)
      seen.textContent = point
        ? new Intl.DateTimeFormat(this.el.dataset.locale || "en", {
            dateStyle: "medium",
            timeStyle: "short",
          }).format(new Date(point[2] * 1000))
        : ""
  },
  selectDay(day) {
    const selected = this.points.filter((point) => {
      const date = new Intl.DateTimeFormat("en-CA", {
        timeZone: this.zone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date(point[2] * 1000))
      return date === day
    })
    this.selectedDay = this.selectedDay === day ? null : day
    this.route(this.selectedDay ? selected : this.points)
  },
  clear(hidden = true) {
    this.generation++
    this.controller?.abort()
    this.controller = null
    this.replayer?.clear()
    this.replayer = null
    for (const marker of this.markers) {
      marker.getElement?.()?.removeAttribute?.("src")
      marker.remove()
    }
    this.markers = []
    this.map?.remove()
    this.map = null
    this.points = []
    this.selectedDay = null
    this.routeOptions = null
    this.library = null
    clearGalleries(this.el)
    this.latest(null)
    const canvas = this.el.querySelector("[data-public-canvas]")
    if (canvas) {
      canvas.hidden = true
      canvas.replaceChildren()
    }
    const empty = this.el.querySelector("[data-public-empty]")
    if (empty) empty.hidden = false
    const content = this.el.querySelector("[data-public-content]")
    if (content) content.hidden = hidden
  },
  disconnected() {
    this.clear(true)
  },
  reconnected() {
    this.pushEvent("public_reload", {})
  },
  destroyed() {
    this.clear(true)
    for (const ref of this.listeners) this.removeHandleEvent(ref)
    this.listeners = []
    this.el.removeEventListener("input", this.input)
    this.el.removeEventListener("toggle", this.toggle, true)
    this.el.removeEventListener("click", this.click)
  },
}
