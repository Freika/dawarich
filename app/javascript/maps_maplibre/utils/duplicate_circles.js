import { createCircle } from "maps_maplibre/utils/geometry"

/**
 * The visit-radius circles of a group of possible duplicate places, and the
 * bounds that hold them all.
 * @param {Array<{lat: number, lon: number, radius: number, color: string}>} places
 * @returns {{collection: Object, bounds: Array}} GeoJSON and [[west, south], [east, north]]
 */
export function duplicateCircles(places) {
  const features = places.map((place) => ({
    type: "Feature",
    properties: { color: place.color },
    geometry: {
      type: "Polygon",
      coordinates: [createCircle([place.lon, place.lat], place.radius)],
    },
  }))
  const coords = features.flatMap((feature) => feature.geometry.coordinates[0])
  const lngs = coords.map(([lng]) => lng)
  const lats = coords.map(([, lat]) => lat)

  return {
    collection: { type: "FeatureCollection", features },
    bounds: [
      [Math.min(...lngs), Math.min(...lats)],
      [Math.max(...lngs), Math.max(...lats)],
    ],
  }
}
