import { RouteSegmenter } from "../algorithms/route_segmenter.js"
import { createReader } from "../data/reader.js"
import { createStatsLayer } from "../public/stats.js"
import { createPublicStatsReader } from "../public/stats_reader.js"
import { createMapRuntime } from "../runtime/create_map.js"
import { TripPlanLayer } from "../trip/plan.js"
export function createPreviewOwner({
  element,
  config,
  reader = config.kind === "stats" ? createPublicStatsReader() : createReader(),
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  loadStyle = async (state, { signal }) => {
    const response = await fetch(
      `/maps_maplibre/styles/${state.styleName === "dark" ? "dark" : "light"}.json`,
      { signal, credentials: "same-origin" },
    )
    if (!response.ok) throw new Error("Style unavailable")
    return response.json()
  },
}) {
  let library, plan, current, map, stats
  function clear() {
    if (!map) return
    stats?.destroy()
    stats = null
    plan?.remove()
    plan = null
    for (const id of ["preview-route", "hexagons-line", "hexagons-fill"])
      if (map.getLayer(id)) map.removeLayer(id)
    for (const id of ["preview-route", "hexagons"])
      if (map.getSource(id)) map.removeSource(id)
  }
  function render() {
    if (!current) return
    clear()
    const { data, state } = current
    if (state.kind === "stats") {
      stats = createStatsLayer({
        map,
        library,
        locale: state.locale,
        timezone: state.range?.timezone,
        labels: state.labels,
      })
      stats.show(data)
    } else if (data.path?.length) {
      const lines = RouteSegmenter.unwrapCoordinates(
        data.path.map(([longitude, latitude]) => ({ longitude, latitude })),
      )
      map.addSource("preview-route", {
        type: "geojson",
        data: {
          type: "Feature",
          properties: {},
          geometry: { type: "MultiLineString", coordinates: lines },
        },
      })
      map.addLayer({
        id: "preview-route",
        type: "line",
        source: "preview-route",
        layout: { "line-join": "round", "line-cap": "round" },
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.9,
        },
      })
      const bounds = new library.LngLatBounds()
      for (const line of lines) for (const point of line) bounds.extend(point)
      if (!bounds.isEmpty())
        map.fitBounds(bounds, { padding: 20, maxZoom: 15, animate: false })
    } else if (data.plan?.features?.length) {
      plan = new TripPlanLayer(map, {
        library,
        numbered: state.numbered === true,
      })
      plan.add(data.plan)
    }
  }
  return createMapRuntime({
    element,
    config: {
      ...config,
      mapOptions: {
        center: [0, 0],
        zoom: 2,
        interactive: config.interactive === true,
      },
    },
    reader,
    loadLibrary: async (options) => {
      library = await loadLibrary(options)
      return library
    },
    loadStyle,
    attach: ({ map: owned, lifetime, operation }) => {
      map = owned
      lifetime.own(() => {
        current = null
        clear()
      })
      map.on("style.load", render)
      lifetime.own(() => map.off("style.load", render))
      return operation.wait(
        new Promise((resolve) => {
          const ready = () => resolve()
          if (map.loaded()) ready()
          else {
            map.once("load", ready)
            lifetime.own(() => map.off("load", ready))
          }
        }),
      )
    },
    refresh: async ({ config: state, operation, signal }) => {
      let data
      if (state.kind === "stats")
        data = (
          await operation.wait(
            reader.read("hexagons", { uuid: state.uuid }, { signal }),
          )
        ).data
      else if (state.tripId)
        data = (
          await operation.wait(
            reader.read("trip", { id: state.tripId }, { signal }),
          )
        ).data
      else if (state.range?.startAt && state.range?.endAt) {
        const points = await operation.wait(
          reader.pages(
            "points",
            {
              start_at: state.range.startAt,
              end_at: state.range.endAt,
              import_id: state.range.importId,
            },
            { signal },
          ),
        )
        data = {
          path: points
            .slice()
            .sort((a, b) => a.timestamp - b.timestamp)
            .map((p) => [Number(p.longitude), Number(p.latitude)]),
        }
      }
      if (!data) data = { path: [] }
      operation.check()
      current = { data, state }
      render()
      if (state.kind === "stats" && state.bounds?.point_count > 0) {
        const b = state.bounds
        map.fitBounds(
          [
            [b.min_lng, b.min_lat],
            [b.max_lng, b.max_lat],
          ],
          { padding: 20, duration: 0 },
        )
      }
    },
    events: {
      refreshed: () => {
        element.dataset.mapState = "ready"
      },
      error: () => {
        current = null
        clear()
        element.dataset.mapState = "failed"
      },
    },
  })
}
