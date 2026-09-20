import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/editing/edit_success_indicator.js",
    import.meta.url,
  ),
  "utf8",
)
const url = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { EditSuccessIndicator } = await import(url)

function fakeMap() {
  const filters = []
  const paints = []
  return {
    filters,
    paints,
    getLayer: () => ({ id: "success" }),
    setFilter: (...args) => filters.push(args),
    setPaintProperty: (...args) => paints.push(args),
  }
}

test("success uses a 550ms local halo and then clears it", (t) => {
  const callbacks = []
  const originalWindow = globalThis.window
  const originalRaf = globalThis.requestAnimationFrame
  const originalCancel = globalThis.cancelAnimationFrame
  globalThis.window = { matchMedia: () => ({ matches: false }) }
  globalThis.requestAnimationFrame = (callback) => {
    callbacks.push(callback)
    return callbacks.length
  }
  globalThis.cancelAnimationFrame = () => {}
  t.after(() => {
    globalThis.window = originalWindow
    globalThis.requestAnimationFrame = originalRaf
    globalThis.cancelAnimationFrame = originalCancel
  })
  const map = fakeMap()
  const indicator = new EditSuccessIndicator(map)
  const startedAt = performance.now()

  indicator.show(42)
  callbacks.shift()(startedAt + 1_000)

  assert.deepEqual(map.filters[0][1], ["==", ["get", "id"], 42])
  assert.deepEqual(map.filters.at(-1)[1], ["==", ["get", "id"], -1])
})

test("reduced motion uses a static 800ms outline", (t) => {
  const originalWindow = globalThis.window
  const originalSetTimeout = globalThis.setTimeout
  let delay
  globalThis.window = { matchMedia: () => ({ matches: true }) }
  globalThis.setTimeout = (_callback, milliseconds) => {
    delay = milliseconds
    return 1
  }
  t.after(() => {
    globalThis.window = originalWindow
    globalThis.setTimeout = originalSetTimeout
  })
  const map = fakeMap()

  new EditSuccessIndicator(map).show(42)

  assert.equal(delay, 800)
  assert.ok(
    map.paints.some(
      ([, property, value]) =>
        property === "circle-stroke-opacity" && value === 1,
    ),
  )
})
