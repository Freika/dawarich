function visitHaloFilter(layer) {
  const filter = layer.filter
  if (
    layer.id !== "visits-halo" ||
    !Array.isArray(filter) ||
    filter.length !== 3 ||
    filter[0] !== "==" ||
    !Array.isArray(filter[1]) ||
    filter[1].length !== 2 ||
    filter[1][0] !== "get" ||
    filter[1][1] !== "id" ||
    !Number.isSafeInteger(filter[2])
  )
    return
  return ["==", ["get", "id"], filter[2]]
}
const properties = new Set([
  "id",
  "name",
  "title",
  "timestamp",
  "start_at",
  "end_at",
  "avg_speed",
  "transportation_mode",
  "color",
  "icon",
  "tag_ids",
  "emoji",
  "confidence",
  "status",
  "duration",
  "distance",
  "anomaly",
  "visit_id",
  "place_id",
])
const geometryTypes = new Set([
  "Point",
  "MultiPoint",
  "LineString",
  "MultiLineString",
  "Polygon",
  "MultiPolygon",
])

function paintValue(value, budget, depth = 0) {
  if (depth > 8 || budget.left-- <= 0) return undefined
  if (typeof value === "string") return value.slice(0, 256)
  if (typeof value === "boolean" || Number.isFinite(value)) return value
  if (Array.isArray(value) && value.length <= 128) {
    const copy = value.map((entry) => paintValue(entry, budget, depth + 1))
    if (copy.every((entry) => entry !== undefined)) return copy
  }
  return undefined
}

function coordinates(value, depth = 0) {
  if (depth > 6) return []
  if (Array.isArray(value))
    return value.slice(0, 1000).map((item) => coordinates(item, depth + 1))
  return Number.isFinite(value) ? value : null
}
function feature(value) {
  const data = typeof value.toJSON === "function" ? value.toJSON() : value
  const selected = Object.fromEntries(
    Object.entries(data.properties ?? {})
      .filter(
        ([key, value]) =>
          properties.has(key) &&
          ["string", "number", "boolean"].includes(typeof value),
      )
      .map(([key, value]) => [
        key,
        typeof value === "string" ? value.slice(0, 256) : value,
      ]),
  )
  return {
    type: "Feature",
    id: data.id,
    properties: selected,
    geometry: geometryTypes.has(data.geometry?.type)
      ? {
          type: data.geometry.type,
          coordinates: coordinates(data.geometry.coordinates),
        }
      : null,
  }
}
function hitCoordinates(geometry) {
  if (!geometry || !Array.isArray(geometry.coordinates)) return null
  if (geometry.type === "Point") return geometry.coordinates
  if (geometry.type === "LineString")
    return geometry.coordinates[Math.floor(geometry.coordinates.length / 2)]
  if (geometry.type === "Polygon") {
    const ring = geometry.coordinates[0]
    if (
      !ring?.length ||
      ring.some(
        (point) =>
          !Array.isArray(point) ||
          point.length !== 2 ||
          !point.every(Number.isFinite),
      )
    )
      return null
    return [0, 1].map(
      (axis) =>
        (Math.min(...ring.map((point) => point[axis])) +
          Math.max(...ring.map((point) => point[axis]))) /
        2,
    )
  }
  return null
}
function hitPosition(map, geometry) {
  const coordinate = hitCoordinates(geometry)
  if (
    !coordinate ||
    coordinate.length !== 2 ||
    !coordinate.every(Number.isFinite) ||
    Math.abs(coordinate[0]) > 180 ||
    Math.abs(coordinate[1]) > 90
  )
    return null
  try {
    const point = map.project?.(coordinate)
    const bounds = map.getContainer?.().getBoundingClientRect()
    if (
      Number.isFinite(point?.x) &&
      Number.isFinite(point?.y) &&
      point.x >= 0 &&
      point.y >= 0 &&
      point.x <= bounds?.width &&
      point.y <= bounds?.height
    )
      return { x: point.x, y: point.y }
  } catch {}
  return null
}
function viewportBounds(map) {
  const box = map.getBounds?.()
  if (!box) return null
  const result = {
    west: box.getWest(),
    south: box.getSouth(),
    east: box.getEast(),
    north: box.getNorth(),
  }
  return Object.values(result).every(Number.isFinite) ? result : null
}

export function installMapDiagnostics({ element, map, getConfig }) {
  let active = true
  const snapshot = ({ sourceId, sourceLayer } = {}) => {
    if (!active) return null
    const style = map.getStyle?.() ?? {}
    const sources = Object.keys(style.sources ?? {}).slice(0, 128)
    let rows = []
    if (sources.includes(sourceId)) {
      try {
        const input = map.getSource?.(sourceId)?.serialize?.().data
        rows =
          input?.type === "FeatureCollection" && Array.isArray(input.features)
            ? input.features
            : map.querySourceFeatures(
                sourceId,
                sourceLayer ? { sourceLayer } : {},
              )
      } catch {}
    }
    let rendered = new Set()
    try {
      const ids = (style.layers ?? [])
        .filter((layer) => layer.source === sourceId)
        .map((layer) => layer.id)
      if (ids.length)
        rendered = new Set(
          (map.queryRenderedFeatures?.(undefined, { layers: ids }) ?? [])
            .slice(0, 5000)
            .map((row) => String(row.properties?.id ?? row.id)),
        )
    } catch {}
    const paintBudget = { left: 4096 }
    const config = getConfig()
    const center = map.getCenter?.()
    return {
      center: center ? { lng: center.lng, lat: center.lat } : null,
      zoom: map.getZoom?.() ?? null,
      bounds: viewportBounds(map),
      bearing: map.getBearing?.() ?? null,
      pitch: map.getPitch?.() ?? null,
      projection: map.getProjection?.()?.type ?? null,
      revision: config.revision,
      styleName: config.styleName,
      range: {
        startAt: config.range?.startAt,
        endAt: config.range?.endAt,
        timezone: config.range?.timezone,
      },
      sources,
      layers: (style.layers ?? []).slice(0, 512).map((layer) => ({
        id: layer.id,
        type: layer.type,
        source: layer.source,
        visibility: layer.layout?.visibility ?? "visible",
        filter: visitHaloFilter(layer),
        paint: Object.fromEntries(
          Object.entries(layer.paint ?? {})
            .slice(0, 32)
            .map(([key, value]) => [key, paintValue(value, paintBudget)])
            .filter(([, value]) => value !== undefined),
        ),
      })),
      hasSource: sources.includes(sourceId),
      featureCount: rows.length,
      features: rows.slice(0, 500).map((row) => {
        const data = feature(row)
        return {
          ...data,
          screen: hitPosition(map, data.geometry),
          rendered: rendered.has(String(data.properties.id ?? data.id)),
        }
      }),
    }
  }
  element.dawarichMapSnapshot = snapshot
  return () => {
    active = false
    map = null
    getConfig = null
    if (element.dawarichMapSnapshot === snapshot)
      delete element.dawarichMapSnapshot
  }
}
