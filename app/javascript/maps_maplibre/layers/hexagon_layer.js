import maplibregl from "maplibre-gl"
import { Toast } from "../components/toast"
import { resolutionForZoom } from "../utils/h3_resolution"
import { ProgressiveLoader } from "../utils/progressive_loader"
import { BaseLayer } from "./base_layer"

const ZOOM_DEBOUNCE_MS = 250

let h3Module = null
let h3LoadingPromise = null

async function loadH3() {
  if (h3Module) return h3Module
  if (!h3LoadingPromise) h3LoadingPromise = import("h3-js")
  h3Module = await h3LoadingPromise
  return h3Module
}

export class HexagonLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "hexagons", ...options })
    this.api = options.api
    this.controller = options.controller
    this.aggregator = new Map()
    this.rawBuffer = []
    this.currentRes = resolutionForZoom(map.getZoom())
    this.lastFetchedPage = 0
    this.loader = null
    this._loadGeneration = 0
    this.hoveredId = null
    this.popup = new maplibregl.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 8,
    })
    this._mousemoveHandler = (e) => this._onMouseMove(e)
    this._mouseleaveHandler = () => this._onMouseLeave()
    this._hoverAttached = false
    this._quotaWarned = false
    this._zoomDebounceTimer = null
    this._zoomHandler = () => {
      if (this._zoomDebounceTimer) clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = setTimeout(() => {
        this._zoomDebounceTimer = null
        this._handleZoomEnd()
      }, ZOOM_DEBOUNCE_MS)
    }
    this.map.on("zoomend", this._zoomHandler)
    this._styleHandler = () => {
      if (!this.visible) return
      if (this.map.getSource(this.sourceId)) return
      this.add(this.data || { type: "FeatureCollection", features: [] })
    }
    this.map.on("styledata", this._styleHandler)
  }

  _handleZoomEnd() {
    if (!this.visible) return
    if (!h3Module) return
    const newRes = resolutionForZoom(this.map.getZoom())
    if (newRes === this.currentRes) return

    this.currentRes = newRes
    this.cancel()
    this._reaggregateFromBuffer()
    this._repaint()
    void this.resumeLoad().catch(() => {})
  }

  _attachHoverHandlers() {
    if (this._hoverAttached) return
    this.map.on("mousemove", "hexagons-fill", this._mousemoveHandler)
    this.map.on("mouseleave", "hexagons-fill", this._mouseleaveHandler)
    this._hoverAttached = true
  }

  _detachHoverHandlers() {
    if (!this._hoverAttached) return
    this.map.off("mousemove", "hexagons-fill", this._mousemoveHandler)
    this.map.off("mouseleave", "hexagons-fill", this._mouseleaveHandler)
    this._hoverAttached = false
  }

  _onMouseMove(e) {
    if (!e.features?.length) return
    const feature = e.features[0]
    const id = feature.id
    if (this.hoveredId !== id) {
      if (this.hoveredId != null) {
        this.map.setFeatureState(
          { source: this.sourceId, id: this.hoveredId },
          { hover: false },
        )
      }
      this.hoveredId = id
      this.map.setFeatureState({ source: this.sourceId, id }, { hover: true })
    }
    this.map.getCanvas().style.cursor = "pointer"
    const count = feature.properties.count
    this.popup
      .setLngLat(e.lngLat)
      .setHTML(`<strong>${count.toLocaleString()}</strong> points`)
      .addTo(this.map)
  }

  _onMouseLeave() {
    if (this.hoveredId != null) {
      this.map.setFeatureState(
        { source: this.sourceId, id: this.hoveredId },
        { hover: false },
      )
      this.hoveredId = null
    }
    this.map.getCanvas().style.cursor = ""
    this.popup.remove()
  }

  add(data) {
    super.add(data)
    this._attachHoverHandlers()
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
      promoteId: "h3_index",
    }
  }

  getLayerConfigs() {
    return [
      {
        id: "hexagons-fill",
        type: "fill",
        source: this.sourceId,
        paint: {
          "fill-color": [
            "interpolate",
            ["linear"],
            ["get", "log_count"],
            0,
            "#1E3A8A",
            1,
            "#3B82F6",
            2,
            "#06B6D4",
            3,
            "#0D9488",
            4,
            "#F59E0B",
          ],
          "fill-opacity": 0.6,
        },
      },
      {
        id: "hexagons-outline",
        type: "line",
        source: this.sourceId,
        paint: {
          "line-color": [
            "case",
            ["boolean", ["feature-state", "hover"], false],
            "rgba(255,255,255,0.95)",
            "rgba(255,255,255,0.35)",
          ],
          "line-width": [
            "case",
            ["boolean", ["feature-state", "hover"], false],
            2,
            1,
          ],
        },
      },
    ]
  }

  async reload({ start_at, end_at }) {
    this.cancel()
    this.aggregator = new Map()
    this.rawBuffer = []
    this.lastFetchedPage = 0
    this._quotaWarned = false
    this._repaint()
    await this.load({ start_at, end_at })
  }

  async load({ start_at, end_at }) {
    this.startAt = start_at
    this.endAt = end_at
    this.currentRes = resolutionForZoom(this.map.getZoom())
    this.aggregator = new Map()
    this.rawBuffer = []
    this.lastFetchedPage = 0
    this._repaint()

    this.controller?.showLoading?.()

    const generation = ++this._loadGeneration
    await loadH3()
    if (generation !== this._loadGeneration) return

    this.loader = new ProgressiveLoader({
      onProgress: ({ newData, currentPage, loaded }) => {
        if (generation !== this._loadGeneration) return
        if (newData?.length) {
          this._aggregatePoints(newData)
          this._repaint()
        }
        this.lastFetchedPage = Math.max(this.lastFetchedPage, currentPage)
        this.controller?.updateLoadingCounts?.({
          counts: { hexagons: loaded },
          isComplete: false,
        })
      },
    })

    try {
      const result = await this.loader.load(
        ({ page, per_page, signal }) =>
          this.api
            .fetchPoints({
              start_at: this.startAt,
              end_at: this.endAt,
              page,
              per_page,
              signal,
            })
            .then((r) => ({
              data: r.points,
              totalPages: r.totalPages,
            })),
        {
          batchSize: 1000,
          maxConcurrent: 3,
          maxPoints: 100_000,
        },
      )

      if (generation !== this._loadGeneration) return
      if (result.length >= 100_000 && !this._quotaWarned) {
        this._quotaWarned = true
        Toast.warning(
          "Showing the first 100,000 points in this range — narrow the date range for denser detail.",
        )
      }
      this.controller?.updateLoadingCounts?.({
        counts: { hexagons: result.length },
        isComplete: true,
      })
      this.controller?.hideLoading?.()
    } catch (error) {
      if (generation !== this._loadGeneration) return
      console.error("HexagonLayer load failed:", error)
      this.controller?.hideLoading?.()
      if (error.name !== "AbortError" && error.message !== "Load cancelled") {
        Toast.error(`Couldn't load hexagons: ${error.message}`)
      }
      throw error
    }
  }

  async resumeLoad() {
    if (!this.startAt || !this.endAt) return

    const generation = ++this._loadGeneration
    await loadH3()
    if (generation !== this._loadGeneration) return

    this.loader = new ProgressiveLoader({
      onProgress: ({ newData, currentPage, loaded }) => {
        if (generation !== this._loadGeneration) return
        if (newData?.length) {
          this._aggregatePoints(newData)
          this._repaint()
        }
        this.lastFetchedPage = Math.max(this.lastFetchedPage, currentPage)
        this.controller?.updateLoadingCounts?.({
          counts: { hexagons: loaded },
          isComplete: false,
        })
      },
    })

    try {
      await this.loader.load(
        ({ page, per_page, signal }) =>
          this.api
            .fetchPoints({
              start_at: this.startAt,
              end_at: this.endAt,
              page,
              per_page,
              signal,
            })
            .then((r) => ({ data: r.points, totalPages: r.totalPages })),
        {
          batchSize: 1000,
          maxConcurrent: 3,
          maxPoints: Math.max(0, 100_000 - this.rawBuffer.length),
          resumeFrom: this.lastFetchedPage + 1,
        },
      )

      if (generation !== this._loadGeneration) return
      this.controller?.updateLoadingCounts?.({
        counts: { hexagons: this.rawBuffer.length },
        isComplete: true,
      })
      this.controller?.hideLoading?.()
    } catch (error) {
      if (generation !== this._loadGeneration) return
      console.error("HexagonLayer resumeLoad failed:", error)
      this.controller?.hideLoading?.()
      if (error.name !== "AbortError" && error.message !== "Load cancelled") {
        Toast.error(`Couldn't load hexagons: ${error.message}`)
      }
      throw error
    }
  }

  cancel() {
    this.loader?.cancel?.()
    this.loader = null
    this._loadGeneration += 1
  }

  dispose() {
    this.cancel()
    this.popup.remove()
    this.hoveredId = null
    this.map.getCanvas().style.cursor = ""
    this.aggregator = new Map()
    this.rawBuffer = []
    this.lastFetchedPage = 0
    this._quotaWarned = false
    this._repaint()
  }

  _recordCell(cell, ts) {
    const existing = this.aggregator.get(cell)
    if (existing) {
      existing.count += 1
      if (ts != null) {
        if (existing.earliest == null || ts < existing.earliest) {
          existing.earliest = ts
        }
        if (existing.latest == null || ts > existing.latest) {
          existing.latest = ts
        }
      }
    } else {
      this.aggregator.set(cell, { count: 1, earliest: ts, latest: ts })
    }
  }

  _aggregatePoints(points) {
    const { latLngToCell } = h3Module
    for (const point of points) {
      const lat = parseFloat(point.latitude)
      const lng = parseFloat(point.longitude)
      if (Number.isNaN(lat) || Number.isNaN(lng)) continue

      const ts = point.timestamp
      const cell = latLngToCell(lat, lng, this.currentRes)
      this._recordCell(cell, ts)
      this.rawBuffer.push({ lat, lng, ts })
    }
  }

  _buildFeatureCollection() {
    const features = []
    if (!h3Module) return { type: "FeatureCollection", features }
    const { cellToBoundary } = h3Module
    for (const [h3Index, data] of this.aggregator) {
      const boundary = cellToBoundary(h3Index)
      const ring = boundary.map(([lat, lng]) => [lng, lat])
      ring.push(ring[0])
      features.push({
        type: "Feature",
        id: h3Index,
        geometry: { type: "Polygon", coordinates: [ring] },
        properties: {
          h3_index: h3Index,
          count: data.count,
          log_count: Math.log10(data.count),
        },
      })
    }
    return { type: "FeatureCollection", features }
  }

  _repaint() {
    const fc = this._buildFeatureCollection()
    this.data = fc
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(fc)
    }
  }

  _reaggregateFromBuffer() {
    this.aggregator = new Map()
    if (!h3Module) return
    const { latLngToCell } = h3Module
    for (const { lat, lng, ts } of this.rawBuffer) {
      const cell = latLngToCell(lat, lng, this.currentRes)
      this._recordCell(cell, ts)
    }
  }

  remove() {
    if (this._zoomDebounceTimer) {
      clearTimeout(this._zoomDebounceTimer)
      this._zoomDebounceTimer = null
    }
    this._detachHoverHandlers()
    this.popup.remove()
    this.hoveredId = null
    this.map.off("zoomend", this._zoomHandler)
    this.map.off("styledata", this._styleHandler)
    super.remove()
  }
}
