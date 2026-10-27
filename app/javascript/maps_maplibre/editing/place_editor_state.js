export function panelState(_previous, action) {
  if (action.close) return { id: null, open: false, editing: false }
  return { id: Number(action.id), open: true, editing: action.edit === true }
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
