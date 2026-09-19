import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_controller.js",
    import.meta.url,
  ),
  "utf8",
)

const importedNames = []
const body = source.replace(
  /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
  (_statement, clause) => {
    const named = clause.match(/\{([\s\S]*)\}/)?.[1] ?? ""
    for (const part of named.split(",")) {
      const name = part
        .trim()
        .split(/\s+as\s+/)
        .pop()
      if (name) importedNames.push(name)
    }
    const defaultName = clause
      .replace(/\{[\s\S]*\}/, "")
      .replace(",", "")
      .trim()
    if (defaultName) importedNames.push(defaultName)
    return ""
  },
)
const stubs = importedNames
  .map((name) =>
    name === "Controller"
      ? "class Controller {}"
      : `const ${name} = new Proxy(function () {}, { get: () => () => {} })`,
  )
  .join("\n")
const { default: MapController } = await import(
  `data:text/javascript;base64,${Buffer.from(`${stubs}\n${body}`).toString("base64")}`
)

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
  const controller = Object.create(MapController.prototype)
  const tracksLayer = {
    sourceId: "tracks-selection-source",
    selectedFeature,
    segmentsActive,
    data: { type: "FeatureCollection", features: [] },
    setSelectedTrack(feature, options = {}) {
      selections.push({ feature, options })
    },
  }
  controller.map = {
    getSource: () => null,
    fitBounds: (bounds) => fits.push(bounds),
  }
  controller.layerManager = {
    getLayer: (name) => (name === "tracks" ? tracksLayer : null),
  }
  controller.api = { fetchTrackWithSegments: async () => fullTrack }
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
