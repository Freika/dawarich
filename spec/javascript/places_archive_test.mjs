import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const strip = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const load = (source) =>
  import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )
const { ApiClient } = await load(
  strip(await read("maps_maplibre/services/api_client.js")),
)
const { PlacesManager } = await load(`
  const SettingsManager = { updateSetting() {} }
  ${strip(await read("controllers/maps/maplibre/places_tag_filters.js")).replace(/^export /gm, "")}
  ${strip(await read("controllers/maps/maplibre/places_manager.js"))}
`)
const { DataLoader } = await load(`
  const createCircle = () => []
  const performanceMonitor = { mark() {}, measure() {} }
  const visitsToGeoJSON = () => ({ features: [] })
  ${strip(await read("controllers/maps/maplibre/data_loader.js"))}
`)

function setup() {
  const requests = []
  const layer = {
    data: { features: [] },
    update(data) {
      this.data = data
    },
  }
  const settings = {}
  const api = {
    async fetchPlaces(options) {
      requests.push(options)
      return [
        { id: 1 },
        ...(options.includeArchived ? [{ id: 2, archived: true }] : []),
      ]
    },
  }
  const manager = new PlacesManager({
    settings,
    api,
    dataLoader: new DataLoader(),
    layerManager: { getLayer: () => layer },
  })
  manager.getSelectedPlaceTags = () => [11, "untagged"]
  return { manager, requests, layer, settings, api }
}

test("archived toggle includes archived places with the selected tags and hides them again", async () => {
  const { manager, requests, layer } = setup()
  await manager.toggleArchivedPlaces({ target: { checked: true } })
  assert.deepEqual(requests.at(-1), {
    tag_ids: [11, "untagged"],
    includeArchived: true,
  })
  assert.deepEqual(
    layer.data.features.map((f) => f.properties.id),
    [1, 1, 2, 2],
  )
  await manager.toggleArchivedPlaces({ target: { checked: false } })
  assert.equal(requests.at(-1).includeArchived, undefined)
  assert.deepEqual(
    layer.data.features.map((f) => f.properties.id),
    [1, 1],
  )
})

test("a late archived filter response cannot restore places after the toggle is off", async () => {
  const { manager, api, layer } = setup()
  const pending = []
  api.fetchPlaces = () => new Promise((resolve) => pending.push(resolve))
  const first = manager.toggleArchivedPlaces({ target: { checked: true } })
  const second = manager.toggleArchivedPlaces({ target: { checked: false } })
  pending[1]([{ id: 1 }])
  await second
  pending[0]([{ id: 2, archived: true }])
  await first
  assert.deepEqual(
    layer.data.features.map((f) => f.properties.id),
    [1, 1],
  )
})

test("archiving a saved place removes it by default and restoring it brings it back", () => {
  const { manager, layer } = setup()
  manager._refreshSavedPlace(layer, { id: 1 }, null)
  manager._refreshSavedPlace(layer, { id: 1, archived: true }, null)
  assert.equal(layer.data.features.length, 0)
  manager._refreshSavedPlace(layer, { id: 1, archived: false }, null)
  assert.equal(layer.data.features.length, 2)
  manager.settings.showArchivedPlaces = true
  manager._refreshSavedPlace(layer, { id: 1, archived: true }, null)
  assert.equal(layer.data.features.length, 2)
  assert.equal(layer.data.features[0].properties.archived, true)
})

test("map refreshes retain the archived toggle and tag selection", async () => {
  const { api, settings, requests } = setup()
  settings.placesEnabled = true
  settings.showArchivedPlaces = true
  settings.pointsVisible = false
  settings.placesTagFilters = [11, "untagged"]
  const loader = new DataLoader(api, "test-key", settings)
  await loader.fetchMapData("2026-10-01", "2026-10-27")
  assert.deepEqual(requests, [
    { tag_ids: [11, "untagged"], includeArchived: true },
  ])
})

test("places API combines active and paginated archived results with tags and privacy masking", async () => {
  const originalFetch = globalThis.fetch
  const urls = []
  globalThis.fetch = async (url) => {
    const parsed = new URL(url, "http://localhost")
    urls.push(parsed)
    const archived = parsed.searchParams.get("filter") === "archived"
    const page = Number(parsed.searchParams.get("page"))
    return {
      ok: true,
      headers: {
        get: (key) => String(key === "X-Total-Pages" && archived ? 2 : page),
      },
      json: async () => [{ id: archived ? page + 1 : 1, archived }],
    }
  }
  try {
    const places = await new ApiClient("test-key").fetchPlaces({
      tag_ids: [11, "untagged"],
      includeArchived: true,
    })
    assert.deepEqual(
      places.map((place) => place.id),
      [1, 2, 3],
    )
    assert.equal(urls.length, 3)
    for (const url of urls) {
      assert.deepEqual(url.searchParams.getAll("tag_ids[]"), ["11", "untagged"])
      assert.equal(url.searchParams.get("mask_privacy_zones"), "true")
    }
    assert.equal(
      urls.filter((url) => url.searchParams.get("filter") === "archived")
        .length,
      2,
    )
  } finally {
    globalThis.fetch = originalFetch
  }
})
