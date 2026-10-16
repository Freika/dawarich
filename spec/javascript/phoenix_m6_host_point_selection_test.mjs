import assert from "node:assert/strict"
import test from "node:test"
import { Element, fixture } from "./support/native_m6_host_fixture.mjs"

function setup(zoom) {
  const f = fixture({
    uiLabels: {
      "map_info.overlapping_points": "{count} overlapping points",
      "map_info.location_coordinates": "{latitude}, {longitude}",
    },
  })
  const summary = new Element()
  f.nodes.set("[data-map-point-summary]", summary)
  f.map.getZoom = () => zoom
  f.map.getMaxZoom = () => 22
  return { ...f, summary }
}

test("native merged point zooms toward an individually selectable marker", async () => {
  const f = setup(16)
  let flight
  f.map.easeTo = (options) => {
    flight = options
  }
  try {
    await f.owner.mount()
    f.map.emit("click:points-mvt", {
      lngLat: { lng: 13.4, lat: 52.5 },
      features: [{ properties: { id: 7, count: 2 } }],
    })
    assert.deepEqual(flight?.center, { lng: 13.4, lat: 52.5 })
    assert.equal(flight?.zoom, 18)
    assert.equal(
      f.pushed.some(({ event }) => event === "address:open"),
      false,
    )
  } finally {
    f.owner.destroy()
  }
})

test("native overlapping points at maximum zoom expose no arbitrary deletion target", async () => {
  const f = setup(22)
  try {
    await f.owner.mount()
    f.map.emit("click:points-mvt", {
      lngLat: { lng: 13.4, lat: 52.5 },
      features: [{ properties: { id: 7, count: 2 } }],
    })
    assert.equal(f.summary.textContent, "2 overlapping points")
    assert.equal(
      f.pushed.some(({ event }) => event === "address:open"),
      false,
    )
    assert.equal(
      f.pushed.some(({ event }) => event === "address:close"),
      true,
    )
  } finally {
    f.owner.destroy()
  }
})

test("native point click takes priority over an overlapping route", async () => {
  const f = setup(16)
  try {
    await f.owner.mount()
    f.map.queryRenderedFeatures = (_point, { layers }) =>
      layers.includes("points-mvt")
        ? [{ properties: { id: 7, count: 1 } }]
        : [{ properties: { id: 9 } }]
    f.map.emit("click", { point: { x: 1, y: 1 } })
    assert.equal(
      f.pushed.some(({ event }) => event === "map:select"),
      false,
    )
    assert.equal(
      f.pushed.some(({ event }) => event === "track:close"),
      true,
    )
  } finally {
    f.owner.destroy()
  }
})

test("native merged point hover advertises zoom and editor hover advertises dragging", async () => {
  const f = setup(16)
  const canvas = { style: {} }
  f.map.getCanvas = () => canvas
  try {
    await f.owner.mount()
    f.map.emit("mousemove:points-mvt", {
      features: [{ properties: { count: 2 } }],
    })
    assert.equal(canvas.style.cursor, "zoom-in")
    f.owner.editor.setEditable(true)
    f.owner.editor.selectPoint({
      properties: { id: 7, longitude: 13, latitude: 52 },
    })
    f.map.emit("mouseenter:track-points")
    assert.equal(canvas.style.cursor, "grab")
  } finally {
    f.owner.destroy()
  }
})

test("native editing refuses a merged tile even when it carries one point id", async () => {
  const f = setup(16)
  f.map.getCanvasContainer = () => ({ style: {} })
  f.map.queryRenderedFeatures = () => [
    {
      geometry: { type: "Point", coordinates: [13, 52] },
      properties: { id: 7, count: 2, longitude: 13, latitude: 52 },
    },
  ]
  try {
    await f.owner.mount()
    await f.owner.update({ ...f.owner.config, editEnabled: true })
    f.map.emit("mousedown", {
      point: { x: 0, y: 0 },
      lngLat: { lng: 13, lat: 52 },
      preventDefault() {},
    })
    f.map.emit("mousemove", {
      point: { x: 8, y: 8 },
      lngLat: { lng: 14, lat: 53 },
    })
    await new Promise((resolve) => setImmediate(resolve))
    f.map.emit("mouseup", { lngLat: { lng: 14, lat: 53 } })
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(
      f.pushed.some(({ event }) => event === "point:move"),
      false,
    )
    assert.equal(Boolean(f.owner.editor.data), false)
  } finally {
    f.owner.destroy()
  }
})
