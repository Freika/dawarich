import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/layers/fog_layer.js",
    import.meta.url,
  ),
  "utf8",
)
const stubbed = source.replace(
  /^import[\s\S]*?from "[^"]+"\n/gm,
  "class FogHexagonSource { }\n",
)
const { FogLayer } = await import(
  `data:text/javascript;base64,${Buffer.from(stubbed).toString("base64")}`
)

function fakeMap() {
  const listeners = new Map()
  return {
    on(event, handler) {
      listeners.set(event, [...(listeners.get(event) || []), handler])
    },
    off(event, handler) {
      listeners.set(
        event,
        (listeners.get(event) || []).filter((other) => other !== handler),
      )
    },
    listenerCount: (event) => (listeners.get(event) || []).length,
    getContainer: () => ({
      offsetWidth: 800,
      offsetHeight: 600,
      appendChild() {},
    }),
  }
}

test("map listeners detach on remove, including the move and zoom handlers", () => {
  globalThis.document = {
    createElement: () => ({
      style: {},
      getContext: () => ({}),
      remove() {},
    }),
  }
  const map = fakeMap()
  const fog = new FogLayer(map, { visible: false })
  fog.add()

  assert.equal(map.listenerCount("move"), 1)

  fog.remove()

  for (const event of ["move", "zoom", "resize", "zoomend"]) {
    assert.equal(map.listenerCount(event), 0)
  }
})

test("fog loads the map's current range and shows the status message it is given", async () => {
  const appended = []
  globalThis.document = {
    createElement: () => ({ style: {}, setAttribute() {} }),
  }
  const map = {
    ...fakeMap(),
    getZoom: () => 5,
    getContainer: () => ({ appendChild: (node) => appended.push(node) }),
  }
  let range = { startAt: "2024-06-01", endAt: "2024-06-30" }
  const loads = []
  const fog = new FogLayer(map, {
    visible: true,
    api: {},
    dateRange: () => range,
    snapshotId: "snap-1",
    statusMessages: { calculating: "Calculating…" },
  })
  fog.hexSource = {
    metadata: { status: "calculating" },
    load: async (_api, params) => {
      loads.push(params)
      return false
    },
  }

  await fog._ensureHexagons()
  range = { startAt: "2024-07-01", endAt: "2024-07-31" }
  await fog._ensureHexagons()

  assert.deepEqual(loads, [
    { start_at: "2024-06-01", end_at: "2024-06-30", snapshot_id: "snap-1" },
    { start_at: "2024-07-01", end_at: "2024-07-31", snapshot_id: "snap-1" },
  ])
  assert.equal(appended[0].textContent, "Calculating…")
})
