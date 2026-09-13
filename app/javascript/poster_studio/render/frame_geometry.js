// Poster frame geometry, shared by the studio's save guard and mirrored by
// Posters::Generate#track_intersects_area?. Latitude bounds come from the same
// Mercator framing render.mjs uses, so the guard and the render agree.
export const POSTER_FRAME = { width: 1200, height: 1600 }

const TILE_PIXELS = 512
const METERS_PER_PIXEL_AT_ZOOM_0 = 40075016.686 / TILE_PIXELS

function worldPixels(lat, distance) {
  const metersPerPixel = (2 * distance) / 3 / POSTER_FRAME.height
  const cosLat = Math.min(
    Math.max(Math.abs(Math.cos((lat * Math.PI) / 180)), 0.01),
    1,
  )
  const zoom = Math.log2((METERS_PER_PIXEL_AT_ZOOM_0 * cosLat) / metersPerPixel)
  return TILE_PIXELS * 2 ** zoom
}

function mercatorToLatitude(y) {
  return ((2 * Math.atan(Math.E ** y) - Math.PI / 2) * 180) / Math.PI
}

export function frameBounds(lat, distance) {
  const world = worldPixels(lat, distance)
  const half = (Math.PI * POSTER_FRAME.height) / world
  const centre = Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360))

  return {
    south: mercatorToLatitude(centre - half),
    north: mercatorToLatitude(centre + half),
    lonDelta: (180 * POSTER_FRAME.width) / world,
  }
}

export function longitudeWithin(pointLon, centreLon, lonDelta) {
  if (lonDelta >= 180) return true

  const wrapped = (((pointLon - centreLon + 180) % 360) + 360) % 360

  return Math.abs(wrapped - 180) <= lonDelta
}

export function frameCovers(coords, lat, lon, distance) {
  const { south, north, lonDelta } = frameBounds(lat, distance)

  return coords.some(
    ([pointLon, pointLat]) =>
      pointLat >= south &&
      pointLat <= north &&
      longitudeWithin(pointLon, lon, lonDelta),
  )
}
