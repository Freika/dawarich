const arrayValue = Array.isArray
const finiteNumber = Number.isFinite
function visitHaloFilter(layer) {
  const filter = layer.filter
  if (
    layer.id !== "visits-halo" ||
    !arrayValue(filter) ||
    filter.length !== 3 ||
    filter[0] !== "==" ||
    !arrayValue(filter[1]) ||
    filter[1].length !== 2 ||
    filter[1][0] !== "get" ||
    filter[1][1] !== "id" ||
    !Number.isSafeInteger(filter[2])
  )
    return
  return structuredClone(filter)
}
const properties =
  "id,name,title,timestamp,start_at,end_at,avg_speed,transportation_mode,color,icon,tag_ids,emoji,confidence,status,duration,distance,anomaly,visit_id,place_id".split(
    ",",
  )
const geometryTypes =
  "Point,MultiPoint,LineString,MultiLineString,Polygon,MultiPolygon".split(",")

function paintValue(value, budget, depth = 0) {
  if (depth > 8 || budget.left-- <= 0) return undefined
  if (typeof value === "string") return value.slice(0, 256)
  if (typeof value === "boolean" || finiteNumber(value)) return value
  if (arrayValue(value) && value.length <= 128) {
    const copy = value.map((entry) => paintValue(entry, budget, depth + 1))
    if (copy.every((entry) => entry !== undefined)) return copy
  }
}

function coordinates(value, depth = 0) {
  if (depth > 6) return []
  if (arrayValue(value))
    return value.slice(0, 1000).map((item) => coordinates(item, depth + 1))
  return finiteNumber(value) ? value : null
}
function feature(value) {
  const data = typeof value.toJSON === "function" ? value.toJSON() : value
  return {
    type: "Feature",
    id: data.id,
    properties: Object.fromEntries(
      Object.entries(data.properties ?? {}).flatMap(([key, value]) =>
        properties.includes(key) &&
        ["string", "number", "boolean"].includes(typeof value)
          ? [[key, typeof value === "string" ? value.slice(0, 256) : value]]
          : [],
      ),
    ),
    geometry: geometryTypes.includes(data.geometry?.type)
      ? {
          type: data.geometry.type,
          coordinates: coordinates(data.geometry.coordinates),
        }
      : null,
  }
}
function hitCoordinates(geometry) {
  if (!geometry || !arrayValue(geometry.coordinates)) return null
  if (geometry.type === "Point") return geometry.coordinates
  if (geometry.type === "LineString")
    return geometry.coordinates[Math.floor(geometry.coordinates.length / 2)]
  if (geometry.type === "Polygon") {
    const ring = geometry.coordinates[0]
    if (
      !ring?.length ||
      ring.some(
        (point) =>
          !arrayValue(point) ||
          point.length !== 2 ||
          !point.every(finiteNumber),
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
  if (geometry?.type?.startsWith("Multi"))
    return (
      geometry.coordinates
        ?.map((coordinates) =>
          hitPosition(map, { type: geometry.type.slice(5), coordinates }),
        )
        .find(Boolean) ?? null
    )
  const coordinate = hitCoordinates(geometry)
  if (
    !coordinate ||
    coordinate.length !== 2 ||
    !coordinate.every(finiteNumber) ||
    Math.abs(coordinate[0]) > 180 ||
    Math.abs(coordinate[1]) > 90
  )
    return null
  try {
    const point = map.project?.(coordinate)
    const bounds = map.getContainer?.().getBoundingClientRect()
    if (
      finiteNumber(point?.x) &&
      finiteNumber(point?.y) &&
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
  return Object.values(result).every(finiteNumber) ? result : null
}

export function installMapDiagnostics({ element, map, getConfig }) {
  let active = true
  const snapshot = ({ sourceId, sourceLayer } = {}) => {
    if (!active) return null
    const style = map.getStyle?.() ?? {}
    const styleLayers = style.layers ?? []
    const sources = Object.keys(style.sources ?? {}).slice(0, 128)
    let rows = []
    if (sources.includes(sourceId)) {
      try {
        const input = map.getSource?.(sourceId)?.serialize?.().data
        const features =
          input?.type === "Feature"
            ? [input]
            : input?.type === "FeatureCollection"
              ? input.features
              : null
        rows = arrayValue(features)
          ? features
          : map.querySourceFeatures(
              sourceId,
              sourceLayer ? { sourceLayer } : {},
            )
      } catch {}
    }
    const paintBudget = { left: 4096 }
    let rendered
    if (sourceId && map.queryRenderedFeatures) {
      rendered = Object.create(null)
      const layers = styleLayers
        .filter((layer) => layer.source === sourceId)
        .map((layer) => layer.id)
      try {
        for (const row of (layers.length
          ? map.queryRenderedFeatures({ layers })
          : []
        ).slice(0, 1000)) {
          const id = row.properties?.id
          rendered[id] ??= []
          rendered[id].push(row.geometry)
        }
      } catch {}
    }
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
      layers: styleLayers.slice(0, 512).map((layer) => ({
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
        const geometries = rendered
          ? (rendered[data.properties.id] ?? [])
          : [data.geometry]
        const screen =
          geometries
            .map((geometry) => hitPosition(map, geometry))
            .find(Boolean) ?? null
        return {
          ...data,
          screen,
          rendered: !!rendered?.[data.properties.id]?.length,
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
