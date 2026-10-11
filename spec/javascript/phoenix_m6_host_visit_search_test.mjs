import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

const all = (node) => [node, ...node.children.flatMap(all)]

test("native host visit search groups in profile year and opens a scoped visit dialog", async () => {
  const f = fixture(),
    panel = new Element()
  f.nodes.set("[data-map-search-visits]", panel)
  f.map.flyTo = () => {}
  f.reader.read = async () => ({
    data: {
      total_locations: 1,
      locations: [
        {
          place_name: "Cafe",
          coordinates: [52, 13],
          visits: [
            {
              date: "2023-12-31T23:30:00Z",
              coordinates: [52, 13],
              visit_details: {
                start_time: "2023-12-31T23:30:00Z",
                end_time: "2024-01-01T00:30:00Z",
              },
            },
          ],
        },
      ],
    },
  })
  await f.owner.mount()
  await f.owner.search.results.open({ name: "Cafe", lat: 52, lon: 13 })
  assert.ok(all(panel).some((node) => node.textContent === "2024 · 1"))
  all(panel)
    .find((node) => node["data-visit-index"] === "0")
    .emit("click")
  assert.equal(
    f.pushed.find((item) => item.event === "visit:new").payload.started_at,
    "2023-12-31T23:30:00Z",
  )
  f.owner.search.results.clear()
  assert.deepEqual(panel.children, [])
  f.owner.destroy()
})

test("native visit selection uses the Rails bounded camera transition", async () => {
  const f = fixture()
  const flights = []
  f.map.flyTo = (options) => flights.push(options)
  f.map.getZoom = () => 2
  f.reader.pages = async () => [
    { id: 7, place: { latitude: 52.52, longitude: 13.405 } },
  ]
  try {
    await f.owner.mount()
    await f.owner.visits.select({ id: 7 })
    assert.deepEqual(flights[0].center, [13.405, 52.52])
    assert.equal(flights[0].zoom, 15)
    assert.equal(flights[0].duration, 600)
  } finally {
    f.owner.destroy()
  }
})

test("native visit pointer survives unrelated timeline pointer-out", async () => {
  const f = fixture({ visitsEnabled: true })
  const canvas = { style: {} }
  let hit = true
  f.map.getCanvas = () => canvas
  f.map.queryRenderedFeatures = (_point, { layers }) =>
    hit && layers.includes("visits") ? [{ properties: { id: 7 } }] : []
  try {
    await f.owner.mount()
    f.map.emit("mousemove", { point: { x: 20, y: 20 } })
    assert.equal(canvas.style.cursor, "pointer")
    f.root.emit("pointerout", { target: { closest: () => null } })
    assert.equal(canvas.style.cursor, "pointer")
    hit = false
    f.map.emit("mousemove", { point: { x: 30, y: 30 } })
    assert.equal(canvas.style.cursor, "")
  } finally {
    f.owner.destroy()
  }
})
