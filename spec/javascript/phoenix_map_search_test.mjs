import assert from "node:assert/strict"
import { test } from "node:test"
import { createLocationSearch } from "../../app-phoenix/assets/js/map/data/location_search.js"
import { createSearchUi } from "../../app-phoenix/assets/js/map/ui/search.js"
import { fitRoute } from "../../app-phoenix/assets/js/map/ui/search_results.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}

function readerMock() {
  const calls = []
  return {
    calls,
    read(resource, params, { signal } = {}) {
      const request = deferred()
      calls.push({ resource, params, signal, request })
      return request.promise
    },
  }
}

const suggestion = (name) => ({
  name,
  address: `${name} street`,
  coordinates: [52.5, 13.4],
  type: "place",
})

test("older search response cannot replace newer query", async () => {
  const reader = readerMock()
  const search = createLocationSearch({ reader })
  assert.deepEqual(await search.suggest("b"), { status: "ok", suggestions: [] })
  assert.equal(reader.calls.length, 0)

  const older = search.suggest("berl")
  const newer = search.suggest("berlin")
  assert.equal(reader.calls[0].signal.aborted, true)
  reader.calls[1].request.resolve({
    status: "ok",
    data: { suggestions: [suggestion("Berlin")] },
  })
  reader.calls[0].request.resolve({
    status: "ok",
    data: { suggestions: [suggestion("Berl")] },
  })
  assert.deepEqual(await older, { status: "stale" })
  const result = await newer
  assert.equal(result.status, "ok")
  assert.deepEqual(result.suggestions, [
    {
      name: "Berlin",
      address: "Berlin street",
      lat: 52.5,
      lon: 13.4,
      type: "place",
    },
  ])
  assert.deepEqual(reader.calls[1].params, { q: "berlin" })
})

test("selected route fit uses canonical full geometry and current padding", () => {
  const fits = []
  let padding = { top: 10, right: 10, bottom: 10, left: 10 }
  const map = { fitBounds: (bounds, options) => fits.push({ bounds, options }) }
  const geometry = {
    type: "LineString",
    coordinates: [
      [13.4, 52.5],
      [13.9, 52.1],
      [13.1, 52.8],
    ],
  }
  fitRoute({ map, geometry, padding: () => padding })
  padding = { top: 10, right: 400, bottom: 10, left: 10 }
  fitRoute({ map, geometry, padding: () => padding })
  assert.deepEqual(fits[0].bounds, [
    [13.1, 52.1],
    [13.9, 52.8],
  ])
  assert.equal(fits[1].options.padding.right, 400)
  assert.equal(
    fitRoute({
      map,
      geometry: { type: "LineString", coordinates: [] },
      padding: () => padding,
    }),
    false,
  )
  assert.equal(fits.length, 2)
})

function element(tag) {
  const listeners = new Map()
  const node = {
    tag,
    children: [],
    textContent: "",
    hidden: false,
    dataset: {},
    attributes: {},
    value: "",
    addEventListener: (type, fn) => listeners.set(type, fn),
    removeEventListener: (type, fn) =>
      listeners.get(type) === fn && listeners.delete(type),
    setAttribute(name, value) {
      node.attributes[name] = value
    },
    append(child) {
      node.children.push(child)
    },
    replaceChildren(...children) {
      node.children = children
    },
    listeners,
  }
  return node
}

test("Escape cancels search listener and selection", async () => {
  const input = element("input")
  const results = element("ul")
  const timers = new Map()
  let next = 0
  const cancelled = []
  const selected = []
  const pending = deferred()
  const ui = createSearchUi({
    input,
    results,
    document: { createElement: element },
    search: {
      suggest: () => pending.promise,
      cancel: () => cancelled.push(true),
    },
    onSelect: (item) => selected.push(item),
    onCancel: () => cancelled.push("marker"),
    timers: {
      setTimeout: (fn) => {
        next += 1
        timers.set(next, fn)
        return next
      },
      clearTimeout: (id) => timers.delete(id),
    },
  })

  input.value = "<b>Berlin</b>"
  input.listeners.get("input")()
  for (const [id, fn] of [...timers]) {
    timers.delete(id)
    fn()
  }
  pending.resolve({
    status: "ok",
    suggestions: [{ name: "<b>Berlin</b>", address: "", lat: 1, lon: 2 }],
  })
  await pending.promise
  await Promise.resolve()
  assert.equal(results.children.length, 1)
  assert.equal(results.children[0].textContent, "<b>Berlin</b>")

  input.listeners.get("keydown")({ key: "ArrowDown", preventDefault() {} })
  input.listeners.get("keydown")({ key: "Escape", preventDefault() {} })
  assert.deepEqual(cancelled, [true, "marker"])
  assert.equal(results.children.length, 0)
  assert.equal(input.value, "")
  assert.deepEqual(selected, [])

  input.value = "berlin"
  input.listeners.get("input")()
  ui.destroy()
  assert.equal(timers.size, 0)
  assert.equal(input.listeners.size, 0)
})
