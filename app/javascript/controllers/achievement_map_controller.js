import { Controller } from "@hotwired/stimulus"
import { CACHE_PREFIX, readCache, writeCache } from "controllers/snapshot_cache"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

const queue = []
let active = 0
const MAX_CONCURRENT = 2
const RENDER_TIMEOUT = 8000

// Snapshots are oversampled beyond the card's on-page size so they stay crisp
// when the fullscreen showcase scales the card up (1.45–2.1×). JPEG keeps the
// larger renders from blowing up the localStorage cache.
const SNAPSHOT_QUALITY = 0.85

function snapshotPixelRatio() {
  return Math.min(2 * (window.devicePixelRatio || 1), 3)
}

function schedule(task) {
  queue.push(task)
  pump()
}

function pump() {
  while (active < MAX_CONCURRENT && queue.length > 0) {
    active++
    const task = queue.shift()
    task().finally(() => {
      active--
      pump()
    })
  }
}

// localStorage handle for the rendered-snapshot cache; null when storage is
// blocked (private mode, cookies disabled).
function cacheStore() {
  try {
    return window.localStorage
  } catch {
    return null
  }
}

export default class extends Controller {
  static targets = ["host", "pin"]
  static values = {
    lat: Number,
    lng: Number,
    zoom: Number,
    markerLat: Number,
    markerLng: Number,
  }

  connect() {
    if (!this.hasHostTarget) return

    // Paint a cached snapshot the moment the controller boots — no observer,
    // no queue, no map. This is what makes a reload appear instant instead of
    // flashing empty and then filling in.
    const cached = readCache(cacheStore(), this.cacheKey())
    if (cached?.img) {
      this.applyCached(cached)
      return
    }

    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect()
          schedule(() => this.render())
        }
      },
      { rootMargin: "300px" },
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    if (this.map) {
      this.safeRemove(this.map)
      this.map = null
    }
  }

  async render() {
    if (!this.element.isConnected || !this.hasHostTarget) return

    try {
      const style = await getMapStyle("light")
      await this.snapshot(style, this.cacheKey())
    } catch (error) {
      console.error("Achievement card map failed to render:", error)
    }
  }

  // Keyed on the map inputs plus devicePixelRatio only — NOT the pixel size,
  // which is 0 at connect() (before layout) and would never match a value
  // measured later at render time. object-fit: cover absorbs size differences.
  cacheKey() {
    const dpr = window.devicePixelRatio || 1
    return `${CACHE_PREFIX}${this.latValue},${this.lngValue},${this.zoomValue},${this.markerLatValue},${this.markerLngValue},${dpr}`
  }

  applyCached({ img, pin }) {
    // Cancel the entrance flip: a cached card is a reload, not a first reveal,
    // so it should show the map immediately instead of replaying back→front.
    this.element
      .closest(".ach-card-wrap")
      ?.classList.add("ach-card-wrap--instant")

    const image = document.createElement("img")
    image.alt = ""
    image.src = img
    this.hostTarget.replaceChildren(image)
    if (pin) this.applyPin(pin)
  }

  snapshot(style, key) {
    return new Promise((resolve) => {
      const host = this.hostTarget
      const map = new maplibregl.Map({
        container: host,
        style,
        center: [this.lngValue, this.latValue],
        zoom: this.zoomValue,
        interactive: false,
        attributionControl: false,
        preserveDrawingBuffer: true,
        fadeDuration: 0,
        pixelRatio: snapshotPixelRatio(),
      })
      this.map = map

      let settled = false
      // Free the concurrency slot on the FIRST terminal signal — success,
      // error, lost WebGL context, or timeout. A map that never idles (a lost
      // context or a stalled sprite fetch fires neither idle nor error) would
      // otherwise hold its slot forever and stall every remaining card.
      const settle = (capture) => {
        if (settled) return
        settled = true
        clearTimeout(timer)

        if (capture && this.map === map) {
          try {
            const pin = this.computePin(map)
            if (pin) this.applyPin(pin)
            const dataUrl = map
              .getCanvas()
              .toDataURL("image/jpeg", SNAPSHOT_QUALITY)
            const image = document.createElement("img")
            image.alt = ""
            image.src = dataUrl
            host.replaceChildren(image)
            if (dataUrl.length > 1000) {
              writeCache(cacheStore(), key, { img: dataUrl, pin }, Date.now())
            }
          } catch (error) {
            console.error("Achievement card map snapshot failed:", error)
          }
        }

        this.safeRemove(map)
        if (this.map === map) this.map = null
        resolve()
      }

      const timer = setTimeout(() => settle(false), RENDER_TIMEOUT)
      map.once("idle", () => settle(true))
      map.once("error", (event) => {
        console.error("Achievement card map error:", event.error)
        settle(false)
      })
      map
        .getCanvas()
        .addEventListener("webglcontextlost", () => settle(false), {
          once: true,
        })
    })
  }

  safeRemove(map) {
    try {
      map.remove()
    } catch {
      // remove() aborts in-flight tile/sprite requests during teardown, which
      // can throw after a lost context or mid-navigation. Nothing to recover.
    }
  }

  computePin(map) {
    if (!this.hasPinTarget || !this.hasMarkerLatValue) return null

    // map.project returns CSS pixels. Derive the CSS size from the canvas
    // buffer and the map's own pixel ratio — the buffer is oversampled beyond
    // devicePixelRatio, and the host's clientHeight reads 0 mid-animation.
    const point = map.project([this.markerLngValue, this.markerLatValue])
    const canvas = map.getCanvas()
    const ratio = map.getPixelRatio?.() || window.devicePixelRatio || 1
    const width = canvas.width / ratio
    const height = canvas.height / ratio
    if (width === 0 || height === 0) return null

    return {
      x: Math.min(Math.max((point.x / width) * 100, 6), 94),
      y: Math.min(Math.max((point.y / height) * 100, 10), 92),
    }
  }

  applyPin(pin) {
    if (!this.hasPinTarget) return
    this.pinTarget.style.left = `${pin.x.toFixed(1)}%`
    this.pinTarget.style.top = `${pin.y.toFixed(1)}%`
  }
}
