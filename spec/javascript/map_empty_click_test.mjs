import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { strippedSource } from "./support/stripped_source.mjs"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const body = await strippedSource("controllers/maps/maplibre/layer_manager.js")
// Stub every name the manager and its mixins import, except the inlined mixins.
const importedNames = []
for (const path of [
  "controllers/maps/maplibre/layer_manager.js",
  "controllers/maps/maplibre/layer_events.js",
]) {
  for (const [, clause] of (await read(path)).matchAll(
    /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
  )) {
    for (const part of (clause.match(/\{([\s\S]*)\}/)?.[1] ?? "").split(",")) {
      const name = part.trim()
      if (name && name !== "layerEvents" && !importedNames.includes(name))
        importedNames.push(name)
    }
  }
}
const stubs = importedNames
  .map((name) =>
    name === "shouldShowPointPopup"
      ? "const shouldShowPointPopup = (p = {}) => p.id != null"
      : `const ${name} = new Proxy(function () {}, { get: () => () => {} })`,
  )
  .join("\n")
const { LayerManager } = await import(
  `data:text/javascript;base64,${Buffer.from(`${stubs}\n${body}`).toString("base64")}`
)

function mount(rendered) {
  let mapClick = null
  const map = {
    on(event, layerOrHandler) {
      if (event === "click" && typeof layerOrHandler === "function")
        mapClick = layerOrHandler
      return { unsubscribe() {} }
    },
    getLayer: (id) => (rendered[id] ? { id } : undefined),
    queryRenderedFeatures: (_point, { layers }) =>
      layers.flatMap((id) => rendered[id] || []),
    getCanvas: () => ({ style: {} }),
  }
  const calls = []
  const handlers = new Proxy(
    {},
    {
      get: (_target, name) => () => calls.push(name),
    },
  )
  new LayerManager(map, {}, {}, {}).setupLayerEventHandlers(handlers)
  return { calls, click: () => mapClick({ point: { x: 1, y: 1 } }) }
}

const cleared = (calls) => calls.filter((name) => /^clear/.test(String(name)))

test("clicking empty map closes a point opened in the editor", () => {
  const { calls, click } = mount({ "points-mvt": [], "track-points": [] })

  click()

  assert.deepEqual(cleared(calls), [
    "clearTrackSelection",
    "clearPointSelection",
  ])
})

test("clicking another tile point leaves the new point's editor to open", () => {
  const { calls, click } = mount({ "points-mvt": [{ properties: { id: 3 } }] })

  click()

  assert.deepEqual(cleared(calls), ["clearTrackSelection"])
})

test("clicking a point of the open editor keeps everything", () => {
  const { calls, click } = mount({
    "track-points": [{ properties: { id: 3 } }],
  })

  click()

  assert.deepEqual(cleared(calls), [])
})
