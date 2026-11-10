import assert from "node:assert/strict"
import test from "node:test"
import { TimelineMapBridge } from "controllers/maps/maplibre/timeline_map_bridge"

const fullTrack = {
  type: "Feature",
  geometry: {
    type: "LineString",
    coordinates: [
      [12.3, 51.3],
      [12.35, 51.32],
      [12.45, 51.36],
    ],
  },
  properties: { id: 39, start_at: "2026-09-17T07:30:00Z" },
}

function buildController({ selectedFeature, segmentsActive = false }) {
  const fits = []
  const selections = []
  const controller = new TimelineMapBridge({})
  const host = controller.controller
  const tracksLayer = {
    sourceId: "tracks-selection-source",
    selectedFeature,
    segmentsActive,
    data: { type: "FeatureCollection", features: [] },
    setSelectedTrack(feature, options = {}) {
      selections.push({ feature, options })
    },
  }
  host.map = {
    getSource: () => null,
    fitBounds: (bounds) => fits.push(bounds),
  }
  host.layerManager = {
    getLayer: (name) => (name === "tracks" ? tracksLayer : null),
  }
  host.api = { fetchTrackWithSegments: async () => fullTrack }
  return { controller, fits, selections }
}

test("opening a track from a tile click fits the whole track, not the clipped tile piece", async () => {
  const clippedTileFeature = {
    type: "Feature",
    sourceLayer: "tracks",
    geometry: {
      type: "LineString",
      coordinates: [
        [12.34, 51.315],
        [12.36, 51.325],
      ],
    },
    properties: { id: 39, start_at: "2026-09-17T07:30:00Z" },
  }
  const { controller, fits } = buildController({
    selectedFeature: clippedTileFeature,
  })

  await controller.handleEntryClick({ detail: { trackId: 39 } })

  assert.deepEqual(fits.at(-1), [
    [12.3, 51.3],
    [12.45, 51.36],
  ])
})

test("an already canonical selected track is reused without refetching", async () => {
  const { controller, fits } = buildController({ selectedFeature: fullTrack })
  let fetched = false
  controller.api.fetchTrackWithSegments = async () => {
    fetched = true
    return fullTrack
  }

  await controller.handleEntryClick({ detail: { trackId: 39 } })

  assert.equal(fetched, false)
  assert.deepEqual(fits.at(-1), [
    [12.3, 51.3],
    [12.45, 51.36],
  ])
})

test("opening the card of the track already showing its segments keeps them", async () => {
  const { controller, selections } = buildController({
    selectedFeature: fullTrack,
    segmentsActive: true,
  })

  await controller.handleEntryClick({ detail: { trackId: 39 } })

  assert.equal(selections.at(-1).options.preserveSegments, true)
})

test("opening the card of a different track drops the previous segments", async () => {
  const { controller, selections } = buildController({
    selectedFeature: { ...fullTrack, properties: { id: 12 } },
    segmentsActive: true,
  })

  await controller.handleEntryClick({ detail: { trackId: 39 } })

  assert.notEqual(selections.at(-1).options.preserveSegments, true)
})

test("opening a track from the timeline fetches it within the map's date range", async () => {
  const { controller } = buildController({ selectedFeature: null })
  const range = {
    startAt: "2026-09-17T00:00+02:00",
    endAt: "2026-09-17T23:59+02:00",
  }
  controller.layerManager.pointTileRange = range
  const fetches = []
  controller.api.fetchTrackWithSegments = async (...args) => {
    fetches.push(args)
    return fullTrack
  }

  await controller.handleEntryClick({ detail: { trackId: 39 } })

  assert.deepEqual(fetches, [[39, range]])
})
