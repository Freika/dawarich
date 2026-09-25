import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

let source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/scratch_layer.js",
    import.meta.url,
  ),
  "utf8",
)
source = source.replace(/^import .+\n/gm, "")
const dependencies = `
const maplibregl = { addProtocol() {} }
class Protocol { constructor() { this.tile = () => {} } }
class BaseLayer {
  constructor(map, options) { this.map = map; this.id = options.id; this.sourceId = this.id + "-source" }
  add() { this.map.added?.push(this.id) }
  remove() { this.map.removed?.push(this.id) }
  show() { this.visible = true }
}
`
const url = `data:text/javascript;base64,${Buffer.from(dependencies + source).toString("base64")}`
const { ScratchLayer, visitedCountryFilter } = await import(url)
globalThis.document ??= { addEventListener() {}, removeEventListener() {} }

test("visited-country filtering uses only canonical ISO-3 metadata", () => {
  assert.deepEqual(visitedCountryFilter(["DEU", "POL"]), [
    "in",
    ["get", "iso_a3"],
    ["literal", ["DEU", "POL"]],
  ])
})

test("the bundled country source overzooms a native maxzoom-8 PMTiles archive", () => {
  const layer = new ScratchLayer({}, {})

  assert.deepEqual(layer.getSourceConfig(), {
    type: "vector",
    url: "pmtiles:///maps/countries-v2.pmtiles",
    minzoom: 0,
    maxzoom: 8,
  })
  assert.ok(
    layer
      .getLayerConfigs()
      .every((config) => config["source-layer"] === "countries"),
  )
})

test("static membership can render without a history API", async () => {
  const filters = []
  const layer = new ScratchLayer(
    {
      getLayer: () => true,
      setFilter: (_id, filter) => filters.push(filter),
    },
    { visitedIsoA3: ["DEU", "POL"] },
  )

  await layer.add()

  assert.equal(filters.length, 4)
  assert.deepEqual(filters[0], visitedCountryFilter(["DEU", "POL"]))
  assert.deepEqual(layer.visitedIsoA3, ["DEU", "POL"])
  assert.equal(layer.staticMembership, true)
})

test("a failed PMTiles source episode is reported once and can use a fresh archive URL", () => {
  const handlers = new Map()
  const map = {
    on(name, handler) {
      handlers.set(name, handler)
    },
    off(name) {
      handlers.delete(name)
    },
  }
  let failures = 0
  const layer = new ScratchLayer(map, {
    onTileError: () => {
      failures += 1
    },
  })

  layer._watchTileErrors()
  handlers.get("error")({ sourceId: "scratch-source" })
  handlers.get("error")({ sourceId: "scratch-source" })
  assert.equal(failures, 1)

  layer._cacheBuster = 1
  assert.equal(
    layer.getSourceConfig().url,
    "pmtiles:///maps/countries-v2.pmtiles?_=1",
  )
  layer._unwatchTileErrors()
  assert.equal(handlers.has("error"), false)
})

test("visited-country response from an older date range cannot replace a newer one", async () => {
  const requests = []
  const filters = []
  let startAt = "2024-06-01"
  const layer = new ScratchLayer(
    {
      getLayer: () => true,
      setFilter: (_id, filter) => filters.push(filter),
    },
    {
      historyScope: () => ({ startAt, endAt: "2024-06-30" }),
      apiClient: {
        fetchVisitedCountries: (range) =>
          new Promise((resolve) => requests.push({ range, resolve })),
      },
    },
  )

  const older = layer.update()
  startAt = "2024-07-01"
  const newer = layer.update()
  requests[1].resolve({ countries: [{ iso_a3: "FRA" }] })
  await newer
  requests[0].resolve({ countries: [{ iso_a3: "DEU" }] })
  await older

  assert.deepEqual(
    requests.map(({ range }) => range.start_at),
    ["2024-06-01", "2024-07-01"],
  )
  assert.deepEqual(layer.visitedIsoA3, ["FRA"])
  assert.deepEqual(filters.at(-1), visitedCountryFilter(["FRA"]))
})

test("point move refetches the current scope and supersedes an in-flight refresh", async () => {
  const requests = []
  const layer = new ScratchLayer(
    { getLayer: () => false },
    {
      historyScope: () => ({ startAt: "2024-06-01", endAt: "2024-06-30" }),
      apiClient: {
        fetchVisitedCountries: () =>
          new Promise((resolve) => requests.push(resolve)),
      },
    },
  )

  const pending = layer.update()
  layer.onPointMoved({ detail: { visited_countries: { iso_a3: ["POL"] } } })
  requests[1]({ countries: [{ iso_a3: "POL" }] })
  await new Promise(setImmediate)
  requests[0]({ countries: [{ iso_a3: "DEU" }] })
  await pending

  assert.deepEqual(layer.visitedIsoA3, ["POL"])
})

test("each Scratch tab refreshes its own range even when the editor reports no membership change", async () => {
  const requests = []
  const makeLayer = (startAt) =>
    new ScratchLayer(
      { getLayer: () => false },
      {
        historyScope: () => ({ startAt, endAt: "2024-12-31" }),
        apiClient: {
          fetchVisitedCountries: async (scope) => {
            requests.push(scope)
            return {
              countries: [{ iso_a3: startAt === "2024-01-01" ? "DEU" : "FRA" }],
            }
          },
        },
      },
    )
  const broadTab = makeLayer("2024-01-01")
  const narrowTab = makeLayer("2024-07-01")

  broadTab.onPointMoved({ detail: { visited_countries: null } })
  narrowTab.onPointMoved({ detail: { visited_countries: null } })
  await new Promise(setImmediate)

  assert.deepEqual(
    requests.map((scope) => scope.start_at),
    ["2024-01-01", "2024-07-01"],
  )
  assert.deepEqual(broadTab.visitedIsoA3, ["DEU"])
  assert.deepEqual(narrowTab.visitedIsoA3, ["FRA"])
})

test("a point-move response arriving after a month switch cannot restore the old month", async () => {
  let startAt = "2024-06-01"
  const requests = []
  const layer = new ScratchLayer(
    { getLayer: () => false },
    {
      historyScope: () => ({ startAt, endAt: "2024-12-31" }),
      apiClient: {
        fetchVisitedCountries: async (scope) => {
          requests.push(scope)
          return { countries: [{ iso_a3: "FRA" }] }
        },
      },
    },
  )
  layer.visitedIsoA3 = ["DEU"]

  startAt = "2024-07-01"
  layer.onPointMoved({ detail: { visited_countries: { iso_a3: ["POL"] } } })
  await new Promise(setImmediate)

  assert.deepEqual(
    requests.map((scope) => scope.start_at),
    ["2024-07-01"],
  )
  assert.deepEqual(layer.visitedIsoA3, ["FRA"])
})

test("failed point-move membership refresh reports a retry and retries when Scratch is shown", async () => {
  let calls = 0
  const errors = []
  const layer = new ScratchLayer(
    { getLayer: () => false },
    {
      historyScope: () => ({ startAt: "2024-07-01", endAt: "2024-07-31" }),
      apiClient: {
        fetchVisitedCountries: async () => {
          calls += 1
          if (calls === 1) throw new Error("offline")
          return { countries: [{ iso_a3: "FRA" }] }
        },
      },
      onMembershipError: (error) => errors.push(error.message),
    },
  )
  layer.visitedIsoA3 = ["DEU"]

  layer.onPointMoved({ detail: { visited_countries: null } })
  await new Promise(setImmediate)
  assert.deepEqual(errors, ["offline"])
  assert.equal(layer._membershipStale, true)

  layer.show()
  await new Promise(setImmediate)
  assert.equal(calls, 2)
  assert.deepEqual(layer.visitedIsoA3, ["FRA"])
  assert.equal(layer._membershipStale, false)
})

test("a stale failed country request does not report an error after a newer success", async () => {
  const requests = []
  const layer = new ScratchLayer(
    { getLayer: () => false },
    {
      historyScope: () => ({ startAt: "2024-06-01", endAt: "2024-06-30" }),
      apiClient: {
        fetchVisitedCountries: () =>
          new Promise((resolve, reject) => requests.push({ resolve, reject })),
      },
    },
  )

  const older = layer.update()
  const newer = layer.update()
  requests[1].resolve({ countries: [{ iso_a3: "FRA" }] })
  await newer
  requests[0].reject(new Error("old request failed"))
  await older

  assert.deepEqual(layer.visitedIsoA3, ["FRA"])
})

test("scratch attaches immediately and a removed layer ignores its pending country response", async () => {
  let resolveRequest
  const map = {
    added: [],
    removed: [],
    getLayer: () => false,
  }
  const layer = new ScratchLayer(map, {
    historyScope: () => ({ startAt: "2024-06-01", endAt: "2024-06-30" }),
    apiClient: {
      fetchVisitedCountries: () =>
        new Promise((resolve) => {
          resolveRequest = resolve
        }),
    },
  })

  const pendingAdd = layer.add()
  assert.deepEqual(map.added, ["scratch"])
  layer.remove()
  resolveRequest({ countries: [{ iso_a3: "DEU" }] })
  await pendingAdd

  assert.deepEqual(map.added, ["scratch"])
  assert.deepEqual(map.removed, ["scratch"])
  assert.deepEqual(layer.visitedIsoA3, [])
})
