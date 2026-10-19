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
    const starts = (feature.properties?.segments || [])
      .map((segment) => [
        segment.coordinates?.[0] || coordinates[segment.start_index],
        segment.emoji || feature.properties?.dominant_mode_emoji || "📍",
      ])
      .filter(([coordinate]) => coordinate)
    if (!starts.length)
      starts.push([
        coordinates[0],
        feature.properties?.dominant_mode_emoji || "📍",
      ])
    for (const [coordinate, label] of [...starts, [coordinates.at(-1), "🏁"]]) {
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
      const segments = (feature.properties?.segments || []).map((row) =>
        segmentFeature({
          ...row,
          coordinates: segment(row.id)?.geometry.coordinates ?? [],
          track_id: Number(id),
        }),
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
            overlay: () => root.querySelector(".map-button-cluster"),
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
  function segment(id, feature = selected) {
    const row = feature?.properties?.segments?.find(
      (row) => String(row.id) === String(id),
    )
    if (!row) return null
    let coordinates = row.coordinates
    if (!Array.isArray(coordinates) || coordinates.length < 2) {
      const path =
        feature.geometry?.type === "LineString"
          ? feature.geometry.coordinates
          : []
      const first = row.start_index,
        last = row.end_index
      if (
        !Number.isInteger(first) ||
        !Number.isInteger(last) ||
        first < 0 ||
        last <= first ||
        last >= path.length
      )
        return null
      coordinates = path.slice(first, last + 1)
    }
    if (
      coordinates.some(
        (point) =>
          !Array.isArray(point) ||
          point.length !== 2 ||
          !point.every(Number.isFinite) ||
          Math.abs(point[0]) > 180 ||
          Math.abs(point[1]) > 90,
      )
    )
      return null
    return {
      type: "Feature",
      geometry: { type: "LineString", coordinates },
      properties: {},
    }
  }
  function destroy() {
    destroyed = true
    clear()
    requests.destroy()
  }
  return {
    select,
    segment,
    clear,
    destroy,
    get selected() {
      return selected
    },
  }
}
