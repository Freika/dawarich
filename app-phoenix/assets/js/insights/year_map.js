import { RouteSegmenter } from "../map/algorithms/route_segmenter.js"
import { fetchStyle } from "../map/style/load_style.js"

export function createYearMap(
  element,
  {
    observe = (element, changed) => {
      const observer = new IntersectionObserver((entries) => {
        for (const entry of entries) changed(entry.isIntersecting)
      })
      observer.observe(element)
      return () => observer.disconnect()
    },
    fetch = globalThis.fetch,
    loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
    loadStyle = fetchStyle,
  } = {},
) {
  let map,
    pending,
    stop,
    destroyed = false,
    generation = 0
  const clear = () => {
    generation++
    pending?.abort()
    pending = null
    map?.remove()
    map = null
  }
  const visibility = async (visible) => {
    if (!visible || destroyed) {
      clear()
      return
    }
    if (pending || map) return
    const version = ++generation
    const request = new AbortController()
    pending = request
    element.dataset.mapState = "loading"
    try {
      const [response, library, style] = await Promise.all([
        fetch(element.dataset.url, {
          signal: request.signal,
          credentials: "same-origin",
          headers: { accept: "application/json" },
        }),
        loadLibrary(),
        loadStyle(
          { styleName: element.dataset.style || "light" },
          { signal: request.signal },
        ),
      ])
      if (!response.ok) throw new Error("Routes unavailable")
      const data = await response.json()
      if (destroyed || version !== generation || request.signal.aborted) return
      const lines = (data.lines || []).flatMap((line) =>
        RouteSegmenter.unwrapCoordinates(
          line.map(([longitude, latitude]) => ({ longitude, latitude })),
        ),
      )
      if (!lines.length) {
        element.hidden = true
        element.dataset.mapState = "empty"
        return
      }
      element.hidden = false
      map = new library.Map({
        container: element,
        style,
        interactive: false,
        attributionControl: false,
      })
      const draw = () => {
        if (destroyed || version !== generation || !map) return
        map.addSource("year-route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: { type: "MultiLineString", coordinates: lines },
          },
        })
        map.addLayer({
          id: "year-route",
          type: "line",
          source: "year-route",
          paint: { "line-color": "#6366f1", "line-width": 2 },
        })
        const bounds = new library.LngLatBounds()
        for (const line of lines) for (const point of line) bounds.extend(point)
        if (!bounds.isEmpty())
          map.fitBounds(bounds, { padding: 15, maxZoom: 10, duration: 0 })
        element.dataset.mapState = "ready"
      }
      if (map.isStyleLoaded()) draw()
      else map.once("load", draw)
    } catch {
      if (!destroyed && !request.signal.aborted && version === generation) {
        clear()
        element.dataset.mapState = "failed"
      }
    } finally {
      if (pending === request) pending = null
    }
  }
  stop = observe(element, visibility)
  return {
    destroy() {
      if (destroyed) return
      destroyed = true
      stop?.()
      clear()
    },
  }
}
