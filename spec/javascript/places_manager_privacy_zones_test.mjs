import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const { PlacesManager, setPrivacyZonesFingerprint } = await import(
  `data:text/javascript;base64,${Buffer.from(
    `const translate = (k) => k
     const Toast = {}
     const SettingsManager = { updateSetting() {} }
     ${(await read("maps_maplibre/utils/tile_freshness.js")).replace(/^export /gm, "")}
     ${stripImports(await read("controllers/maps/maplibre/places_manager.js"))}
     export { setPrivacyZonesFingerprint }`,
  ).toString("base64")}`
)

function setup(fingerprint) {
  const refreshed = []
  const reloads = []
  const layer = (id) => ({ refresh: () => refreshed.push(id) })
  const placesLayer = {
    visible: true,
    data: { features: [{ properties: { id: 1 } }] },
    update() {},
  }
  const controller = {
    layerManager: {
      getLayer: (id) =>
        id === "places" ? placesLayer : id.endsWith("-mvt") ? layer(id) : null,
    },
    api: { fetchPrivacyZones: async () => ({ zones: [], fingerprint }) },
    dataLoader: {
      placesToGeoJSON: (places) => ({
        features: places.map((p) => ({ properties: { id: p.id } })),
      }),
    },
    settings: {},
    loadMapData: async (options) => reloads.push(options),
  }
  return { manager: new PlacesManager(controller), refreshed, reloads }
}

const placeSaved = { detail: { place: { id: 2 } } }

test("a place edit that changes a zone reloads tiles and map data", async () => {
  setPrivacyZonesFingerprint("old")
  const { manager, refreshed, reloads } = setup("new")

  await manager.handlePlaceCreated(placeSaved)

  assert.deepEqual(refreshed.sort(), ["points-mvt", "tracks-mvt"])
  assert.deepEqual(reloads, [{ showLoading: false, fitBounds: false }])
})

test("a place edit that leaves the zones alone reloads nothing", async () => {
  setPrivacyZonesFingerprint("same")
  const { manager, refreshed, reloads } = setup("same")

  await manager.handlePlaceUpdated(placeSaved)

  assert.deepEqual(refreshed, [])
  assert.deepEqual(reloads, [])
})
