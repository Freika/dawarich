import assert from "node:assert/strict"
import { DataLoader } from "controllers/maps/maplibre/data_loader"

const loader = new DataLoader({}, "test-key", {})
const geojson = loader.visitsToGeoJSON([
  {
    id: 1,
    name: null,
    display_name: "Address only",
    place: null,
    status: "suggested",
  },
  {
    id: 2,
    name: null,
    display_name: "Coffee Shop",
    place: { name: "Coffee Shop", longitude: 13.405, latitude: 52.52 },
    status: "confirmed",
  },
])

assert.equal(geojson.features.length, 1)
assert.deepEqual(
  JSON.parse(JSON.stringify(geojson.features[0].geometry.coordinates)),
  [13.405, 52.52],
)
assert.equal(geojson.features[0].properties.name, "Coffee Shop")

const centered = loader.visitsToGeoJSON([
  { id: 3, place: null, center: { latitude: 52.51, longitude: 13.41 } },
  { id: 4, place: null, center: { latitude: 0, longitude: 0 } },
  {
    id: 5,
    place: { name: "Chosen", latitude: 51, longitude: 12 },
    center: { latitude: 52.51, longitude: 13.41 },
  },
  { id: 6, place: null, center: null },
])
assert.deepEqual(
  JSON.parse(
    JSON.stringify(centered.features.map((f) => f.geometry.coordinates)),
  ),
  [
    [13.41, 52.51],
    [0, 0],
    [12, 51],
  ],
)
