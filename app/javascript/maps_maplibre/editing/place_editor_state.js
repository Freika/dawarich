export function panelState(previous, action) {
  if (action.close) return { id: null, open: false, editing: false }
  const state = {
    id: Number(action.id),
    open: true,
    editing: action.edit === true,
  }
  const returnTo = previous?.open ? previous.returnTo : action.returnTo
  if (returnTo) state.returnTo = returnTo
  return state
}

export function consumePlaceParams(href) {
  const url = new URL(href)
  const id = Number(url.searchParams.get("place_id"))
  if (!Number.isSafeInteger(id) || id <= 0) return null
  const edit = url.searchParams.get("edit") === "1"
  url.searchParams.delete("place_id")
  url.searchParams.delete("edit")
  return { id, edit, url: `${url.pathname}${url.search}${url.hash}` }
}

const earthRadius = 6371000
const radians = (degrees) => (degrees * Math.PI) / 180
const degrees = (radians) => (radians * 180) / Math.PI

export function radiusHandle(center, radius, bearing = Math.PI / 2) {
  const lat = radians(center[1])
  const lon = radians(center[0])
  const angle = radius / earthRadius
  const nextLat = Math.asin(
    Math.sin(lat) * Math.cos(angle) +
      Math.cos(lat) * Math.sin(angle) * Math.cos(bearing),
  )
  const nextLon =
    lon +
    Math.atan2(
      Math.sin(bearing) * Math.sin(angle) * Math.cos(lat),
      Math.cos(angle) - Math.sin(lat) * Math.sin(nextLat),
    )
  return [((degrees(nextLon) + 540) % 360) - 180, degrees(nextLat)]
}

export function radiusFromHandle(center, handle, maximum) {
  const lat1 = radians(center[1])
  const lat2 = radians(handle[1])
  const a =
    Math.sin((lat2 - lat1) / 2) ** 2 +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(radians(handle[0] - center[0]) / 2) ** 2
  const distance = earthRadius * 2 * Math.asin(Math.sqrt(Math.min(1, a)))
  return Math.max(1, Math.min(maximum, Math.round(distance)))
}

export function radiusCircle(center, radius) {
  const ring = Array.from({ length: 64 }, (_, index) => {
    const point = radiusHandle(center, radius, (index / 64) * Math.PI * 2)
    point[0] = center[0] + ((((point[0] - center[0]) % 360) + 540) % 360) - 180
    return point
  })
  return [...ring, ring[0]]
}

export function shouldCenterPlace({ origin, edit }) {
  return origin === "link" || edit === true
}

export function placeBounds(place) {
  const ring = radiusCircle(
    [place.longitude, place.latitude],
    place.visit_radius,
  )
  return [
    [Math.min(...ring.map((p) => p[0])), Math.min(...ring.map((p) => p[1]))],
    [Math.max(...ring.map((p) => p[0])), Math.max(...ring.map((p) => p[1]))],
  ]
}

export function placeCameraOptions(mapRect, panelRect, toolbarRect) {
  const gap = mapRect.width < 400 ? 28 : 60
  const padding = { top: gap, right: gap, bottom: gap, left: gap }
  for (const rect of [panelRect, toolbarRect]) {
    if (!rect || rect.left >= mapRect.right || rect.right <= mapRect.left)
      continue
    const overlap = rect.right - mapRect.left + 24
    if (overlap + gap + 100 < mapRect.width)
      padding.left = Math.max(padding.left, overlap)
  }
  return { padding, maxZoom: 17, duration: 300 }
}

export function selectedPlaceFeatures(place) {
  if (
    !place ||
    ![place.longitude, place.latitude, place.visit_radius].every(
      Number.isFinite,
    )
  )
    return { type: "FeatureCollection", features: [] }
  const center = [place.longitude, place.latitude]
  const color = place.color || "#6366f1"
  return {
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        properties: { id: place.id, featureKind: "center", color },
        geometry: { type: "Point", coordinates: center },
      },
      {
        type: "Feature",
        properties: {
          id: place.id,
          featureKind: "boundary",
          color: place.geofence ? "#f59e0b" : color,
        },
        geometry: {
          type: "Polygon",
          coordinates: [radiusCircle(center, place.visit_radius)],
        },
      },
    ],
  }
}
