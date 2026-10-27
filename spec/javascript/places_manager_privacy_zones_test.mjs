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
     ${stripImports(await read("controllers/maps/maplibre/places_tag_filters.js")).replace(/^export /gm, "")}
     ${stripImports(await read("controllers/maps/maplibre/places_manager.js"))}
     export { setPrivacyZonesFingerprint }`,
  ).toString("base64")}`
)

function setup(fingerprint, failed = false) {
  globalThis.document = { querySelectorAll: () => [] }
  const refreshed = []
  const reloads = []
  const recentPoint = {
    cleared: false,
    clear() {
      this.cleared = true
    },
  }
  const removedAttributes = []
  const layer = (id) => ({ refresh: () => refreshed.push(id) })
  const placesLayer = {
    visible: true,
    data: { features: [{ properties: { id: 1 } }] },
    update() {},
  }
  const controller = {
    layerManager: {
      getLayer: (id) =>
        id === "places"
          ? placesLayer
          : id === "recentPoint"
            ? recentPoint
            : id.endsWith("-mvt")
              ? layer(id)
              : null,
    },
    api: {
      fetchPlaces: async () => [{ id: 2 }],
      fetchPrivacyZones: async () =>
        failed
          ? { zones: [], fingerprint: null, failed }
          : { zones: [], fingerprint },
    },
    dataLoader: {
      placesToGeoJSON: (places) => ({
        features: places.map((p) => ({ properties: { id: p.id } })),
      }),
    },
    settings: {},
    loadMapData: async (options) => reloads.push(options),
    element: { removeAttribute: (name) => removedAttributes.push(name) },
  }
  return {
    manager: new PlacesManager(controller),
    refreshed,
    reloads,
    recentPoint,
    removedAttributes,
  }
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

test("a failed zone request keeps the current zones and reloads nothing", async () => {
  setPrivacyZonesFingerprint("current")
  const { manager, refreshed, reloads } = setup(null, true)

  await manager.handlePlaceUpdated(placeSaved)

  assert.deepEqual(refreshed, [])
  assert.deepEqual(reloads, [])
})

test("a zone change hides the current position until the next live point", async () => {
  setPrivacyZonesFingerprint("before")
  const { manager, recentPoint, removedAttributes } = setup("after")

  await manager.handlePlaceCreated(placeSaved)

  assert.equal(recentPoint.cleared, true)
  assert.deepEqual(removedAttributes, [
    "data-maps--maplibre-current-position-value",
  ])
})

test("unchanged zones keep the current position", async () => {
  setPrivacyZonesFingerprint("steady")
  const { manager, recentPoint } = setup("steady")

  await manager.handlePlaceUpdated(placeSaved)

  assert.equal(recentPoint.cleared, false)
})

test("saving a hidden place removes its feature without fetching the places list", async () => {
  setPrivacyZonesFingerprint("unchanged")
  globalThis.document = { querySelectorAll: () => [] }
  let data = {
    features: [{ properties: { id: 1 } }, { properties: { id: 2 } }],
  }
  const placesLayer = {
    visible: true,
    get data() {
      return data
    },
    update(value) {
      data = value
    },
  }
  let fetches = 0
  const manager = new PlacesManager({
    layerManager: { getLayer: () => placesLayer },
    api: {
      fetchPlaces: async () => {
        fetches += 1
        return [{ id: 1 }, { id: 3 }]
      },
      fetchPrivacyZones: async () => ({ fingerprint: "unchanged" }),
    },
    dataLoader: {
      placesToGeoJSON: (places) => ({
        features: places.map((place) => ({ properties: { id: place.id } })),
      }),
    },
    settings: {},
  })

  await manager.handlePlaceUpdated({
    detail: { removedId: 2 },
  })

  assert.equal(fetches, 0)
  assert.deepEqual(
    data.features.map((feature) => feature.properties.id),
    [1],
  )
})

test("saving a visible place upserts without fetching before a new tag enters map filters", async () => {
  setPrivacyZonesFingerprint("unchanged")
  globalThis.document = { querySelectorAll: () => [] }
  let data = { features: [] }
  const placesLayer = {
    visible: true,
    get data() {
      return data
    },
    update(value) {
      data = value
    },
  }
  let fetches = 0
  const manager = new PlacesManager({
    layerManager: { getLayer: () => placesLayer },
    api: {
      fetchPlaces: async () => {
        fetches += 1
        return []
      },
      fetchPrivacyZones: async () => ({ fingerprint: "unchanged" }),
    },
    dataLoader: {
      placesToGeoJSON: (places) => ({
        features: places.map((place) => ({ properties: place })),
      }),
    },
    settings: {},
  })

  await manager.handlePlaceCreated({
    detail: { place: { id: 2, geofence: true, tags: [{ id: 99 }] } },
  })

  assert.equal(fetches, 0)
  assert.deepEqual(
    data.features.map((feature) => feature.properties),
    [{ id: 2, geofence: true, tags: [{ id: 99 }] }],
  )
})
