import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/video_studio/map_effects.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { drawFogOverlay, drawRouteMarker } = await import(moduleUrl)

function recordingContext() {
  const calls = []
  const ctx = {
    calls,
    clearRect: (...args) => calls.push(["clearRect", ...args]),
    fillRect: (...args) => calls.push(["fillRect", ...args]),
    save: () => calls.push(["save"]),
    restore: () => calls.push(["restore"]),
    beginPath: () => calls.push(["beginPath"]),
    moveTo: (...args) => calls.push(["moveTo", ...args]),
    lineTo: (...args) => calls.push(["lineTo", ...args]),
    stroke: () => calls.push(["stroke"]),
    arc: (...args) => calls.push(["arc", ...args]),
    fill: () => calls.push(["fill"]),
  }
  for (const property of [
    "fillStyle",
    "strokeStyle",
    "lineWidth",
    "lineCap",
    "lineJoin",
    "globalCompositeOperation",
  ]) {
    Object.defineProperty(ctx, property, {
      set: (value) => calls.push([property, value]),
    })
  }
  return ctx
}

const map = {
  project: ([x, y]) => ({ x, y }),
  getCanvas: () => ({ clientWidth: 100, clientHeight: 200 }),
}

const route = [
  {
    type: "Feature",
    properties: {},
    geometry: {
      type: "LineString",
      coordinates: [
        [10, 20],
        [30, 40],
      ],
    },
  },
]

test("fog covers the frame and erases the travelled corridor", () => {
  const ctx = recordingContext()
  drawFogOverlay(ctx, {
    map,
    features: route,
    head: [30, 40],
    width: 200,
    height: 400,
    opacity: 0.7,
  })

  assert.ok(ctx.calls.some((call) => call[0] === "fillRect"))
  assert.ok(
    ctx.calls.some(
      (call) =>
        call[0] === "globalCompositeOperation" && call[1] === "destination-out",
    ),
  )
  assert.ok(ctx.calls.some((call) => call[0] === "moveTo" && call[1] === 20))
  assert.ok(ctx.calls.some((call) => call[0] === "lineTo" && call[1] === 60))
  assert.ok(ctx.calls.some((call) => call[0] === "arc" && call[1] === 60))
})

test("a transparent fog clears the old overlay without painting a new one", () => {
  const ctx = recordingContext()
  drawFogOverlay(ctx, { map, width: 200, height: 400, opacity: 0 })

  assert.deepEqual(ctx.calls, [["clearRect", 0, 0, 200, 400]])
})

test("fog uses the selected overlay color", () => {
  const ctx = recordingContext()
  drawFogOverlay(ctx, {
    map,
    width: 200,
    height: 400,
    opacity: 0.7,
    color: "#123456",
  })

  assert.ok(
    ctx.calls.some(
      (call) => call[0] === "fillStyle" && call[1] === "rgba(18, 52, 86, 0.7)",
    ),
  )
})

test("the route marker is scaled from map CSS pixels into the video", () => {
  const ctx = recordingContext()
  drawRouteMarker(ctx, {
    map,
    coordinate: [25, 50],
    width: 200,
    height: 400,
    accent: "#ff0000",
  })

  const arcs = ctx.calls.filter((call) => call[0] === "arc")
  assert.equal(arcs.length, 2)
  assert.deepEqual(arcs[0].slice(1, 3), [50, 100])
  assert.ok(
    ctx.calls.some((call) => call[0] === "fillStyle" && call[1] === "#ff0000"),
  )
})

test("the marker is skipped until the map and coordinate exist", () => {
  const ctx = recordingContext()
  drawRouteMarker(ctx, {
    map: null,
    coordinate: null,
    width: 200,
    height: 400,
  })

  assert.deepEqual(ctx.calls, [])
})
