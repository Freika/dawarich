import assert from "node:assert/strict"
import { test } from "node:test"
import { fixture } from "./support/native_m6_host_fixture.mjs"

const visits = [7, 8].map((id) => ({
  id,
  name: `Visit ${id}`,
  status: "confirmed",
  started_at: "2026-03-29T10:00:00+02:00",
  ended_at: "2026-03-29T11:00:00+02:00",
  place: { longitude: 13, latitude: 52 },
}))
function setup() {
  const f = fixture({ visitsEnabled: true })
  f.reader.pages = async () => visits
  f.flights = []
  f.map.flyTo = (value) => f.flights.push(value)
  f.paints = new Map()
  f.map.setPaintProperty = (id, name, value) =>
    f.paints.set(`${id}:${name}`, value)
  f.canvas = { style: {} }
  f.map.getCanvas = () => f.canvas
  return f
}

test("native visit selection flies to fresh cookie geometry and keeps its halo through viewport refresh", async () => {
  const f = setup()
  try {
    await f.owner.mount()
    await f.owner.visits.select({ id: 7, geometry: [0, 0] })
    assert.deepEqual(f.flights[0].center, [13, 52])
    assert.deepEqual(f.flights[0].padding, {
      top: 50,
      right: 50,
      bottom: 50,
      left: 50,
    })
    assert.deepEqual(f.layers.get("visits-halo").filter, [
      "==",
      ["get", "id"],
      7,
    ])
    await f.owner.entityLayers.update(f.owner.config)
    assert.deepEqual(f.layers.get("visits-halo").filter, [
      "==",
      ["get", "id"],
      7,
    ])
    await f.owner.visits.select({ id: null })
    assert.deepEqual(f.layers.get("visits-halo").filter, [
      "==",
      ["get", "id"],
      -1,
    ])
    await f.owner.visits.select({ id: 999 })
    assert.equal(f.flights.length, 1)
  } finally {
    f.owner.destroy()
  }
})
test("native visit selection refuses late fresh rows after range replacement or owner disposal", async () => {
  const f = setup()
  let resolve
  try {
    await f.owner.mount()
    f.reader.pages = () =>
      new Promise((finish) => {
        resolve = finish
      })
    const pending = f.owner.visits.select({ id: 7 })
    await Promise.resolve()
    f.reader.pages = async () => visits
    await f.owner.update({ ...f.owner.config, revision: 2 })
    resolve(visits)
    await pending
    assert.equal(f.flights.length, 0)
    f.reader.pages = () =>
      new Promise((finish) => {
        resolve = finish
      })
    const disposed = f.owner.visits.select({ id: 7 })
    await Promise.resolve()
    f.owner.destroy()
    resolve(visits)
    await disposed
    assert.equal(f.flights.length, 0)
    assert.equal(f.listeners.get("mousemove").size, 0)
    await f.owner.visits.select({ id: 7 })
    assert.equal(f.flights.length, 0)
  } finally {
    f.owner.destroy()
  }
})
test("native visit timeline hover dims other markers and overlapping time paints while map hover shows a pointer", async () => {
  const f = setup()
  try {
    await f.owner.mount()
    f.layers.set("tracks-mvt", {})
    f.layers.set("points-mvt", {})
    f.root.emit("pointerover", {
      target: {
        closest: (selector) =>
          selector === "[data-entry]"
            ? {
                dataset: {
                  entry: "visit",
                  visitId: "7",
                  startedAt: visits[0].started_at,
                  endedAt: visits[0].ended_at,
                },
              }
            : null,
      },
    })
    assert.deepEqual(f.paints.get("visits:circle-opacity"), [
      "case",
      ["==", ["get", "id"], 7],
      1,
      0.15,
    ])
    assert.equal(f.paints.get("tracks-mvt:line-opacity")[0], "case")
    assert.equal(f.paints.get("points-mvt:circle-opacity")[0], "case")
    f.root.emit("pointerout", {})
    assert.equal(f.paints.get("visits:circle-opacity"), 0.9)
    f.map.queryRenderedFeatures = (_point, { layers }) =>
      layers.includes("visits") ? [{ properties: { id: 7 } }] : []
    f.map.emit("mousemove", { point: { x: 1, y: 2 } })
    assert.equal(f.canvas.style.cursor, "pointer")
    f.map.queryRenderedFeatures = () => []
    f.map.emit("mousemove", { point: { x: 1, y: 2 } })
    assert.equal(f.canvas.style.cursor, "")
  } finally {
    f.owner.destroy()
  }
})

test("native visit hover and pin commands preserve armed drawing and point edit modes", async () => {
  const f = setup()
  const status = { textContent: "placing" }
  f.nodes.set("[data-map-tool-status]", status)
  try {
    await f.owner.mount()
    f.canvas.style.cursor = "crosshair"
    f.map.queryRenderedFeatures = () => [{ properties: { id: 7 } }]
    f.map.emit("mousemove", { point: { x: 1, y: 2 } })
    f.map.emit("click:visits", { features: [{ properties: { id: 7 } }] })
    assert.equal(f.canvas.style.cursor, "crosshair")
    assert.equal(
      f.pushed.filter(({ event }) => event === "map:select").length,
      0,
    )
    status.textContent = ""
    f.owner.config.editEnabled = true
    f.canvas.style.cursor = "move"
    f.map.emit("mousemove", { point: { x: 1, y: 2 } })
    f.map.emit("click:visits", { features: [{ properties: { id: 7 } }] })
    assert.equal(f.canvas.style.cursor, "move")
    assert.equal(
      f.pushed.filter(({ event }) => event === "map:select").length,
      0,
    )
    f.owner.config.editEnabled = false
    f.map.emit("click:visits", { features: [{ properties: { id: 7 } }] })
    assert.deepEqual(
      f.pushed.filter(({ event }) => event === "map:select").at(-1).payload,
      { kind: "visit", id: 7 },
    )
  } finally {
    f.owner.destroy()
  }
})
