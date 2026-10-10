const properties = new Set([
  "id",
  "name",
  "title",
  "timestamp",
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
export function installMapDiagnostics({ element, map, getConfig }) {
  let active = true
  const snapshot = ({ sourceId, sourceLayer } = {}) => {
    if (!active) return null
    const style = map.getStyle?.() ?? {}
    const sources = Object.keys(style.sources ?? {}).slice(0, 128)
    let rows = []
    if (sources.includes(sourceId)) {
      try {
        rows = map.querySourceFeatures(
          sourceId,
          sourceLayer ? { sourceLayer } : {},
        )
      } catch {}
    }
    const config = getConfig()
    const center = map.getCenter?.()
    return {
      center: center ? { lng: center.lng, lat: center.lat } : null,
      zoom: map.getZoom?.() ?? null,
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
        paint: Object.fromEntries(
          Object.entries(layer.paint ?? {}).filter(([, value]) =>
            ["string", "number", "boolean"].includes(typeof value),
          ),
        ),
      })),
      hasSource: sources.includes(sourceId),
      featureCount: rows.length,
      features: rows.slice(0, 500).map(feature),
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
