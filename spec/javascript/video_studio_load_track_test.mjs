import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/video_studio/load_track.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { loadTrack } = await import(moduleUrl)

const TRACK = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      properties: { start_at: "2026-08-20T08:00:00Z" },
      geometry: {
        type: "LineString",
        coordinates: [
          [12.3712, 51.3402],
          [12.376, 51.3402],
        ],
      },
    },
  ],
}

// MapPageProvider.points() awaits ensurePointsLoaded(), and that call is what
// builds the routes GeoJSON and pushes it into the routes layer
// (map_data_manager.js _loadPoints -> _updateLayerBySource("routes", ...)).
// Under tiled rendering nothing else ever fills that layer, so reading the
// track before points() resolves hands back an empty collection.
function lazyProvider() {
  let pointsLoaded = false
  return {
    async points() {
      pointsLoaded = true
      return [
        { longitude: "12.3712", latitude: "51.3402", timestamp: 1_787_212_800 },
      ]
    },
    trackGeojson() {
      return pointsLoaded ? TRACK : { type: "FeatureCollection", features: [] }
    },
  }
}

test("reads the track only after the provider has loaded its points", async () => {
  const { trackGeojson, points } = await loadTrack(lazyProvider())

  assert.equal(trackGeojson.features.length, 1)
  assert.equal(points.length, 1)
})
