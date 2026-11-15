import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import { duplicateCircles } from "maps_maplibre/utils/duplicate_circles"

// A small map of one group of possible duplicates: each place's visit radius
// as a circle in the colour of its row. Browsers cap live WebGL contexts at
// about sixteen, so a map exists only while its group is on screen.
export default class extends Controller {
  static values = {
    places: Array,
    tilesUrl: String,
    tilesFallback: Boolean,
  }

  connect() {
    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting
        if (this.visible) this.show()
        else this.hide()
      },
      { rootMargin: "200px" },
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.visible = false
    this.observer?.disconnect()
    this.hide()
  }

  async show() {
    if (this.map || this.loading) return
    this.loading = true
    const { collection, bounds } = duplicateCircles(this.placesValue)
    const map = await MapInitializer.initialize(this.element, {
      center: bounds[0],
      zoom: 15,
      showControls: false,
      vectorTilesUrl: this.tilesUrlValue || null,
      tilesFallback: this.tilesFallbackValue,
    })
    this.loading = false
    // Scrolled away (or removed) while the map was loading.
    if (!this.visible) {
      map.remove()
      return
    }
    this.map = map
    map.fitBounds(bounds, { padding: 16, duration: 0, maxZoom: 18 })
    const draw = () => {
      map.addSource("duplicates", { type: "geojson", data: collection })
      map.addLayer({
        id: "duplicates-fill",
        type: "fill",
        source: "duplicates",
        paint: { "fill-color": ["get", "color"], "fill-opacity": 0.15 },
      })
      map.addLayer({
        id: "duplicates-line",
        type: "line",
        source: "duplicates",
        paint: { "line-color": ["get", "color"], "line-width": 2 },
      })
    }
    if (map.isStyleLoaded()) draw()
    else map.once("load", draw)
  }

  hide() {
    this.map?.remove()
    this.map = null
  }
}
