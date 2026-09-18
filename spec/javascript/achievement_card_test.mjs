import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/achievement_card_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { default: AchievementCardController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

function fixture(t, { mounted = false, dialogOpen = false } = {}) {
  const intersections = []
  const sizes = []
  const globals = {
    matchMedia: () => ({ matches: false }),
    IntersectionObserver: class {
      constructor(callback) {
        this.callback = callback
        intersections.push(this)
      }
      observe(element) {
        this.element = element
      }
      disconnect() {
        this.disconnected = true
      }
    },
    ResizeObserver: class {
      constructor(callback) {
        this.callback = callback
        sizes.push(this)
      }
      observe(element) {
        this.element = element
      }
      disconnect() {
        this.disconnected = true
      }
    },
    cancelAnimationFrame: () => {},
  }
  for (const [key, value] of Object.entries(globals)) {
    const original = Object.getOwnPropertyDescriptor(globalThis, key)
    Object.defineProperty(globalThis, key, { configurable: true, value })
    t.after(() => {
      if (original) Object.defineProperty(globalThis, key, original)
      else delete globalThis[key]
    })
  }
  const properties = {}
  const svg = {
    style: {
      setProperty(name, value) {
        properties[name] = value
      },
    },
    querySelector: () => ({
      getBBox: () => ({ x: 12, y: 28, width: 276, height: 204 }),
    }),
  }
  const stage = {
    clientWidth: 263,
    clientHeight: 210,
    querySelector: () => svg,
  }
  const card = { style: { removeProperty() {} }, querySelectorAll: () => [] }
  const controller = new AchievementCardController()
  controller.element = {
    querySelector: () => card,
    closest: () => (dialogOpen ? {} : null),
  }
  controller.materialTarget = { querySelector: () => stage }
  controller.hasSilhouetteValue = true
  controller.mounted = mounted
  return { controller, stage, svg, properties, intersections, sizes }
}

test("a mounted card refits synchronously when moved into the preview and back", (t) => {
  const { controller, stage, properties, intersections, sizes } = fixture(t, {
    mounted: true,
  })
  controller.connect()
  const compactScale = properties["--map-scale"]
  controller.disconnect()
  stage.clientWidth = 423
  stage.clientHeight = 407
  controller.connect()
  const previewScale = properties["--map-scale"]
  assert.notEqual(previewScale, compactScale)
  assert.equal(
    intersections.length,
    0,
    "reconnection must not wait for a post-paint intersection callback",
  )
  assert.equal(sizes[0].disconnected, true)
  sizes[1].callback()
  assert.equal(
    properties["--map-scale"],
    previewScale,
    "the later observer must not visibly resize the map",
  )
  controller.disconnect()
  stage.clientWidth = 263
  stage.clientHeight = 210
  controller.connect()
  assert.equal(properties["--map-scale"], compactScale)
})

test("an unmounted card opened directly in a dialog mounts before paint", (t) => {
  const { controller, intersections } = fixture(t, { dialogOpen: true })
  let mounts = 0
  controller.mount = () => {
    mounts += 1
  }
  controller.connect()
  assert.equal(mounts, 1)
  assert.equal(intersections.length, 0)
})

test("ordinary unmounted collection cards still lazy-mount near the viewport", (t) => {
  const { controller, intersections } = fixture(t)
  let mounts = 0
  controller.mount = () => {
    mounts += 1
  }
  controller.connect()
  assert.equal(mounts, 0)
  assert.equal(intersections.length, 1)
  intersections[0].callback([{ isIntersecting: false }])
  assert.equal(mounts, 0)
  intersections[0].callback([{ isIntersecting: true }])
  assert.equal(mounts, 1)
})

test("ResizeObserver continues to fit responsive changes without recreating SVG", (t) => {
  const { controller, stage, svg, properties, sizes } = fixture(t, {
    mounted: true,
  })
  controller.connect()
  const originalScale = properties["--map-scale"]
  stage.clientWidth = 200
  stage.clientHeight = 160
  sizes[0].callback()
  assert.notEqual(properties["--map-scale"], originalScale)
  assert.equal(stage.querySelector("svg"), svg)
})

test("zero-sized hidden stages retain their last valid map scale", (t) => {
  const { controller, stage, properties, sizes } = fixture(t, {
    mounted: true,
  })
  controller.connect()
  const originalScale = properties["--map-scale"]
  stage.clientWidth = 0
  stage.clientHeight = 0
  sizes[0].callback()
  assert.equal(properties["--map-scale"], originalScale)
})
