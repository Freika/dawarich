import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/flight_arcs.js",
    import.meta.url,
  ),
  "utf8",
)
const { arcifyFlights } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

const flight = (coordinates) => ({
  type: "FeatureCollection",
  features: [
    { type: "Feature", geometry: { type: "LineString", coordinates } },
  ],
})

test("a recorded track keeps its own points instead of an arc", () => {
  const track = [
    [13.49, 52.35],
    [10.0, 53.0],
    [8.0, 51.0],
    [2.55, 49.01],
  ]

  const result = arcifyFlights(flight(track))

  assert.deepEqual(result.features[0].geometry.coordinates, track)
})

test("a track crossing the antimeridian is unwrapped into one line", () => {
  const input = flight([
    [170.0, 50.0],
    [179.5, 51.0],
    [-179.5, 52.0],
    [-170.0, 53.0],
  ])

  const coords = arcifyFlights(input).features[0].geometry.coordinates

  assert.deepEqual(
    coords.map(([lon]) => lon),
    [170.0, 179.5, 180.5, 190.0],
  )
  assert.equal(input.features[0].geometry.coordinates[2][0], -179.5)
})

test("a two-point flight still becomes a great-circle arc", () => {
  const coords = arcifyFlights(
    flight([
      [13.49, 52.35],
      [-73.78, 40.64],
    ]),
  ).features[0].geometry.coordinates

  assert.ok(coords.length > 2)
})
