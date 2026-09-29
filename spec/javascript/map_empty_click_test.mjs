import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre/layer_manager.js",
    import.meta.url,
  ),
  "utf8",
)
const importedNames = []
const body = source.replace(
  /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
  (_statement, clause) => {
    for (const part of (clause.match(/\{([\s\S]*)\}/)?.[1] ?? "").split(",")) {
      const name = part.trim()
      if (name) importedNames.push(name)
    }
    return ""
  },
)
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
  return {
    calls,
    click: (event = {}) => mapClick({ point: { x: 1, y: 1 }, ...event }),
  }
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

test("a track click keeps the selection it made in the same event", () => {
  const { calls, click } = mount({ "tracks-mvt": [] })

  click({ defaultPrevented: true })

  assert.deepEqual(cleared(calls), [])
})
