import { eraseMapCanvas } from "./shared_erase.js"

async function loadMap({ signal }) {
  const [maplibre, styles] = await Promise.all([
    import("/maplibre/6.4.1/maplibre-gl.mjs"),
    import("../demo/map_style.js"),
  ])
  const style = await styles.demoStyle(undefined, (url) =>
    fetch(url, { signal }),
  )
  if (!document.getElementById("native-maplibre-css")) {
    const css = document.createElement("link")
    css.id = "native-maplibre-css"
    css.rel = "stylesheet"
    css.href = "/maplibre/6.4.1/maplibre-gl.css"
    document.head.append(css)
  }
  return { maplibre, style }
}

export const FamilyMap = {
  mounted() {
    this.generation = 0
    this.locations = []
    this.markers = []
    this.listeners = [
      this.handleEvent("family-locations", (snapshot) =>
        this.show(snapshot.locations),
      ),
      this.handleEvent("family-clear", () => {
        this.clear()
        this.visibility(true)
      }),
      this.handleEvent("family-focus", ({ id }) => {
        this.focusId = id
        this.focus()
      }),
    ]
  },
  async show(locations) {
    this.clear()
    const generation = this.generation
    const snapshot = locations || []
    if (!snapshot.length) {
      this.visibility(false)
      return
    }
    const controller = new AbortController()
    this.controller = controller
    try {
      const { maplibre, style } = await (this.loader || loadMap)({
        signal: controller.signal,
      })
      if (generation !== this.generation) return
      this.locations = snapshot
      const canvas = this.el.querySelector("[data-family-canvas]")
      canvas.hidden = false
      this.el.querySelector("[data-family-empty]").hidden = true
      const first = this.locations[0]
      this.map = new maplibre.Map({
        container: canvas,
        style,
        center: [first.longitude, first.latitude],
        zoom: 12,
      })
      this.map.addControl(new maplibre.NavigationControl())
      this.markers = this.locations.map((member) =>
        new maplibre.Marker()
          .setLngLat([member.longitude, member.latitude])
          .addTo(this.map),
      )
      if (this.locations.length > 1) {
        const lons = this.locations.map((member) => member.longitude)
        const lats = this.locations.map((member) => member.latitude)
        this.map.fitBounds(
          [
            [Math.min(...lons), Math.min(...lats)],
            [Math.max(...lons), Math.max(...lats)],
          ],
          { padding: 50, maxZoom: 14 },
        )
      }
      this.visibility(false)
      this.focus()
    } catch {
      if (generation === this.generation) this.clear()
    }
  },
  focus() {
    const member = this.locations.find((item) => item.user_id === this.focusId)
    if (member)
      this.map?.flyTo({ center: [member.longitude, member.latitude], zoom: 14 })
  },
  clear() {
    this.generation++
    this.controller?.abort()
    this.controller = null
    for (const marker of this.markers) marker.remove()
    this.markers = []
    this.map?.remove()
    this.map = null
    this.locations = []
    this.focusId = null
    eraseMapCanvas(this.el, "family")
  },
  visibility(hidden) {
    for (const row of this.el
      .closest("#family-shell")
      ?.querySelectorAll(
        "[data-family-member-id], [data-family-last-seen], button[phx-click=family_focus]",
      ) || [])
      row.hidden = hidden
  },
  disconnected() {
    this.clear()
    this.visibility(true)
  },
  reconnected() {
    this.pushEvent("family_reload", {})
  },
  destroyed() {
    this.clear()
    this.visibility(true)
    for (const ref of this.listeners) this.removeHandleEvent(ref)
    this.listeners = []
  },
}
