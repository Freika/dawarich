import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/map_loading.js",
    import.meta.url,
  ),
  "utf8",
)
globalThis.getComputedStyle = (element) => ({ position: element.position })
const { startMapLoading, finishMapLoadingOn } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function fakeContainer(position = "static") {
  const classes = new Set()
  return {
    position,
    style: {},
    classList: {
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
    },
  }
}

test("a map shows the spinner until it has loaded", () => {
  const container = fakeContainer()
  const listeners = {}
  const map = {
    getContainer: () => container,
    once: (event, callback) => {
      listeners[event] = callback
    },
  }

  startMapLoading(container)
  assert.ok(container.classList.contains("map-loading"))
  assert.equal(container.style.position, "relative")

  finishMapLoadingOn(map)
  listeners.load()
  assert.ok(!container.classList.contains("map-loading"))
})

test("a positioned container keeps its own position", () => {
  const container = fakeContainer("absolute")

  startMapLoading(container)

  assert.equal(container.style.position, undefined)
})
