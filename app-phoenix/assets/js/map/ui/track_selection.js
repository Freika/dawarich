import { createRequestScope } from "../data/request_scope.js"
import { pointFeature, segmentFeature } from "../edit/editable_track_data.js"
import { panelPadding } from "./padding.js"
import { fitRoute } from "./search_results.js"

const SOURCE = "native-selected-track"
const LINE = "native-selected-track-line"
const SEGMENTS = "native-selected-track-segments"
const POINTS = "track-points-source"
export function createTrackSelection({
  map,
  reader,
  root,
  library,
  getConfig,
}) {
  const requests = createRequestScope()
  let destroyed = false,
    selected = null,
    markers = []
  function remove(source, layers) {
    for (const id of layers) if (map.getLayer(id)) map.removeLayer(id)
    if (map.getSource(source)) map.removeSource(source)
  }
  function clear() {
    selected = null
    requests.reset()
    remove(SOURCE, [LINE, SEGMENTS])
    remove(POINTS, ["track-points"])
    for (const marker of markers) marker.remove()
    markers = []
  }
  function endpoints(feature) {
    if (!library?.Marker) return
    const lines =
      feature.geometry.type === "MultiLineString"
        ? feature.geometry.coordinates
        : [feature.geometry.coordinates]
    const coordinates = lines.flat()
    for (const [coordinate, label] of [
      [coordinates[0], feature.properties.dominant_mode_emoji || "📍"],
      [coordinates.at(-1), "🏁"],
    ]) {
      if (!coordinate) continue
      const element = root.ownerDocument.createElement("span")
      element.className = "native-track-endpoint"
      element.textContent = label
      markers.push(
        new library.Marker({ element }).setLngLat(coordinate).addTo(map),
      )
    }
  }
  async function select({ id, points = false } = {}) {
    clear()
    if (destroyed || id == null) return
    const operation = requests.begin()
    try {
      const { data: feature } = await operation.wait(
        reader.read(
          "track",
          { id, import_id: getConfig().range.importId },
          { signal: operation.signal },
        ),
      )
      operation.check()
      if (!feature?.geometry || destroyed) return
      selected = feature
      const segments = (feature.properties?.segments || []).map((segment) =>
        segmentFeature({ ...segment, track_id: Number(id) }),
      )
      const data = {
        type: "FeatureCollection",
        features: [
          { ...feature, properties: { ...feature.properties, kind: "track" } },
          ...segments,
        ],
      }
      map.addSource(SOURCE, { type: "geojson", data })
      map.addLayer({
        id: LINE,
        type: "line",
        source: SOURCE,
        filter: ["==", ["get", "kind"], "track"],
        paint: {
          "line-color": getConfig().trackColor || "#6366F1",
          "line-width": 5,
        },
      })
      map.addLayer({
        id: SEGMENTS,
        type: "line",
        source: SOURCE,
        filter: ["==", ["get", "kind"], "segment"],
        paint: {
          "line-color": ["coalesce", ["get", "color"], "#6366F1"],
          "line-width": 6,
        },
      })
      if (map.fitBounds)
        fitRoute({
          map,
          geometry: feature.geometry,
          padding: panelPadding({
            container: map.getContainer(),
            overlay: () => root.querySelector("#native-map-panel"),
          }),
        })
      endpoints(feature)
      if (points) {
        const rows = await operation.wait(
          reader.pages(
            "track_points",
            { id, import_id: getConfig().range.importId },
            { signal: operation.signal },
          ),
        )
        operation.check()
        if (destroyed) return
        map.addSource(POINTS, {
          type: "geojson",
          data: {
            type: "FeatureCollection",
            features: rows.map((row) => pointFeature(row, id)),
          },
        })
        map.addLayer({
          id: "track-points",
          type: "circle",
          source: POINTS,
          paint: { "circle-color": "#10b981", "circle-radius": 5 },
        })
      }
    } catch {
      if (!destroyed && operation.revision === requests.revision) clear()
    } finally {
      operation.close()
    }
  }
  function destroy() {
    destroyed = true
    clear()
    requests.destroy()
  }
  return {
    select,
    clear,
    destroy,
    get selected() {
      return selected
    },
  }
}
