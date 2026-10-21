import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

test("native host search selects a bounded suggestion and fits canonical timeline geometry", async () => {
  const f = fixture()
  const input = new Element(),
    results = new Element()
  let populated
  const ready = new Promise((resolve) => {
    populated = resolve
  })
  const replace = results.replaceChildren.bind(results)
  results.replaceChildren = (...items) => {
    replace(...items)
    if (items.some((item) => item.className?.startsWith("search-result-item")))
      populated()
  }
  f.nodes.set("[data-map-search]", input)
  f.nodes.set("[data-map-suggestions]", results)
  let flown, fitted
  f.map.flyTo = (options) => {
    flown = options
  }
  f.map.fitBounds = (...args) => {
    fitted = args
  }
  f.reader.read = async (resource) =>
    resource === "suggestions"
      ? { data: { suggestions: [{ name: "Berlin", coordinates: [52, 13] }] } }
      : {
          data: {
            geometry: {
              type: "LineString",
              coordinates: [
                [12, 51],
                [14, 53],
              ],
            },
          },
        }
  await f.owner.mount()
  input.value = "Berlin"
  input.emit("input")
  await ready
  input.emit("keydown", { key: "ArrowDown", preventDefault() {} })
  input.emit("keydown", { key: "Enter", preventDefault() {} })
  assert.deepEqual(flown.center, [13, 52])
  f.root.emit("click", {
    target: { closest: () => ({ dataset: { trackId: "7" } }) },
  })
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(fitted[0], [
    [12, 51],
    [14, 53],
  ])
  assert.deepEqual(fitted[1].padding, {
    left: 50,
    right: 50,
    top: 50,
    bottom: 50,
  })
  f.owner.destroy()
  assert.equal(input.listeners.get("input").size, 0)
})

test("native search keeps repeated completed selections until an outside map click", async () => {
  const f = fixture()
  const visits = new Element()
  f.nodes.set("[data-map-suggestions]", visits)
  f.reader.read = async () => ({ data: { locations: [], total_locations: 0 } })
  f.map.flyTo = () => {}
  await f.owner.mount()
  try {
    for (let i = 0; i < 2; i++) {
      await f.owner.search.results.open({
        name: `Berlin ${i}`,
        lat: 52,
        lon: 13,
      })
      assert.equal(visits.classList.contains("hidden"), false)
      assert.ok(visits.children.length > 0)
    }
    f.map.emit("click", { originalEvent: { target: f.element } })
    assert.equal(visits.classList.contains("hidden"), true)
    assert.deepEqual(visits.children, [])
  } finally {
    f.owner.destroy()
  }
})
