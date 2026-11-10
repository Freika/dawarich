import assert from "node:assert/strict"
import test from "node:test"
import { TrackSelection } from "controllers/maps/maplibre/event_handlers"
import { Toast } from "maps_maplibre/components/toast"

function harness(fetchedFeature, pointTileRange = undefined) {
  const shown = []
  const selected = []
  const fetches = []
  const tracksLayer = {
    setSelectedTrack: (feature) => selected.push(feature),
    showSegments: (feature) => shown.push(feature),
    hideSegments: () => {},
    setSegmentHoverCallback: () => {},
    setSegmentLeaveCallback: () => {},
  }
  const selection = new TrackSelection(
    { getLayer: () => null },
    {
      api: {
        fetchTrackWithSegments: async (...args) => {
          fetches.push(args)
          return fetchedFeature
        },
      },
      layerManager: {
        pointTileRange,
        getLayer: (name) => (name === "tracks" ? tracksLayer : null),
      },
    },
  )
  selection._createMarkers = () => {}
  return { selection, shown, selected, fetches }
}

test("a tiled track click fetches the track within the map's date range", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const range = {
    startAt: "2024-06-01T00:00+02:00",
    endAt: "2024-06-01T23:59+02:00",
  }
  const { selection, fetches } = harness({ properties: { id: 7 } }, range)

  await selection.select(fragment)

  assert.deepEqual(fetches, [[7, range]])
})

test("a tiled track click swaps the clipped fragment for the fetched geometry", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const fetched = {
    properties: { id: 7 },
    geometry: {
      type: "LineString",
      coordinates: [
        [0, 0],
        [1, 1],
      ],
    },
  }
  const { selection, shown, selected } = harness(fetched)

  await selection.select(fragment)

  assert.deepEqual(shown, [fetched])
  assert.deepEqual(selected, [fragment, fetched])
  assert.equal(selection.feature, fetched)
})

test("a fetched track without geometry keeps the clicked feature", async () => {
  const fragment = { properties: { id: 7 }, geometry: { type: "LineString" } }
  const { selection, shown, selected } = harness({ properties: { id: 7 } })

  await selection.select(fragment)

  assert.deepEqual(shown, [fragment])
  assert.deepEqual(selected, [fragment])
})

test("a failed detail fetch surfaces a toast", async (t) => {
  const toasts = []
  t.mock.method(Toast, "error", (message) => toasts.push(message))
  t.mock.method(console, "error", () => {})
  const { selection } = harness(null)
  selection.controller.api.fetchTrackWithSegments = async () => {
    throw new Error("network down")
  }

  await selection.select({ properties: { id: 7 } })

  assert.deepEqual(toasts, ["messages.failed_to_load_track_details"])
})

test("a late track-detail response cannot revive a cleared selection", async () => {
  const { selection, shown, selected } = harness(null)
  let resolveFetch
  selection.controller.api.fetchTrackWithSegments = () =>
    new Promise((resolve) => {
      resolveFetch = resolve
    })

  const pending = selection.select({ properties: { id: 7 } })
  assert.equal(selection.clear(), true)
  resolveFetch({ properties: { id: 7 }, geometry: { type: "LineString" } })
  await pending

  assert.deepEqual(shown, [])
  assert.equal(selected.at(-1), null)
  assert.equal(selection.feature, null)
  assert.equal(selection.clear(), false)
})

test("an older track-detail response cannot overwrite a newer click", async () => {
  const { selection, shown } = harness(null)
  const requests = new Map()
  selection.controller.api.fetchTrackWithSegments = (id) =>
    new Promise((resolve) => requests.set(id, resolve))

  const older = selection.select({ properties: { id: 7 } })
  const newer = selection.select({ properties: { id: 8 } })
  requests.get(8)({ properties: { id: 8 }, geometry: { type: "LineString" } })
  await newer
  requests.get(7)({ properties: { id: 7 }, geometry: { type: "LineString" } })
  await older

  assert.deepEqual(
    shown.map((feature) => feature.properties.id),
    [8],
  )
  assert.equal(selection.feature.properties.id, 8)
})

test("a segment mode change reloads the selected track's segments only", async () => {
  const { selection, fetches } = harness({
    properties: { id: 7, segments: [] },
  })
  await selection.select({ properties: { id: 7 } })

  await selection.refreshSegments(8)
  await selection.refreshSegments("7")

  assert.deepEqual(
    fetches.map(([id]) => id),
    [7, 7],
  )
})
