import assert from "node:assert/strict"
import test from "node:test"
import { fixture, Element } from "./support/native_m6_host_fixture.mjs"

test("native host search selects a bounded suggestion and fits canonical timeline geometry", async () => {
  const f = fixture()
  const input = new Element(), results = new Element()
  f.nodes.set("[data-map-search]", input)
  f.nodes.set("[data-map-suggestions]", results)
  let flown, fitted
  f.map.flyTo = options => { flown = options }
  f.map.fitBounds = (...args) => { fitted = args }
  f.reader.read = async resource => resource === "suggestions" ? { data: { suggestions: [{ name: "Berlin", coordinates: [52, 13] }] } } : { data: { geometry: {type: "LineString", coordinates: [[12, 51], [14, 53]]} } }
  await f.owner.mount()
  input.value = "Berlin"
  input.emit("input")
  await new Promise(resolve => setTimeout(resolve, 350))
  input.emit("keydown", { key: "ArrowDown", preventDefault() {} })
  input.emit("keydown", { key: "Enter", preventDefault() {} })
  assert.deepEqual(flown.center, [13, 52])
  f.root.emit("click", { target: {closest: () => ({ dataset: {trackId: "7"} })} })
  await new Promise(resolve => setImmediate(resolve))
  assert.deepEqual(fitted[0], [[12, 51], [14, 53]])
  f.owner.destroy()
  assert.equal(input.listeners.get("input").size, 0)
})
