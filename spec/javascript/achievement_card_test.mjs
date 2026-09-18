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
  `data:text/javascript;base64,${Buffer.from(`const spectralMarkup = (...args) => globalThis.__spectralMarkup(...args)\nclass Controller {}\n${source}`).toString("base64")}`
)

function fixture(
  t,
  {
    mounted = false,
    dialogOpen = false,
    restoredMaterial = false,
    locked = false,
  } = {},
) {
  const intersections = []
  const sizes = []
  const animationFrames = []
  const globals = {
    matchMedia: () => ({ matches: false }),
    requestAnimationFrame: (callback) => animationFrames.push(callback),
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
  const cardProperties = {}
  const gradientAttributes = {}
  const card = {
    style: {
      removeProperty(name) {
        delete cardProperties[name]
      },
      setProperty(name, value) {
        cardProperties[name] = value
      },
    },
    querySelectorAll: () => [
      {
        setAttribute(name, value) {
          gradientAttributes[name] = value
        },
      },
    ],
  }
  const fallbackPath = {
    getAttribute: (name) => (name === "d" ? "M0 0L10 0L10 10Z" : null),
  }
  const fallbackSvg = {
    getAttribute: (name) => (name === "viewBox" ? "0 0 10 10" : null),
    querySelector: () => fallbackPath,
  }
  const controller = new AchievementCardController()
  controller.element = {
    querySelector: () => card,
    closest: () => (dialogOpen ? {} : null),
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 300, height: 450 }),
  }
  controller.materialTarget = {
    querySelector: (selector) => {
      if (selector === ".spectral-fallback svg")
        return restoredMaterial ? null : fallbackSvg
      return stage
    },
  }
  controller.card = card
  controller.lockedValue = locked
  controller.mounted = mounted
  return {
    controller,
    stage,
    svg,
    properties,
    cardProperties,
    gradientAttributes,
    animationFrames,
    intersections,
    sizes,
  }
}

test("locked cards use a neutral accent and ignore pointer tilt, including in preview", (t) => {
  const { controller, cardProperties, gradientAttributes, animationFrames } =
    fixture(t, {
      locked: true,
      dialogOpen: true,
    })
  const original = globalThis.__spectralMarkup
  globalThis.__spectralMarkup = () => ({
    html: '<div class="geo-stage"></div>',
    accent: "#ffba38",
  })
  t.after(() => {
    if (original) globalThis.__spectralMarkup = original
    else delete globalThis.__spectralMarkup
  })

  controller.connect()
  controller.move({ pointerType: "mouse", clientX: 240, clientY: 90 })

  assert.equal(cardProperties["--accent"], "#899297")
  assert.equal(cardProperties["--rx"], undefined)
  assert.equal(cardProperties["--ry"], undefined)
  assert.equal(animationFrames.length, 0)
  assert.deepEqual(gradientAttributes, {})
})

test("unlocked cards retain pointer tilt and foil color shift", (t) => {
  const { controller, cardProperties, gradientAttributes, animationFrames } =
    fixture(t)
  controller.connect()
  controller.move({ pointerType: "mouse", clientX: 240, clientY: 90 })

  assert.equal(animationFrames.length, 1)
  animationFrames[0]()
  assert.notEqual(cardProperties["--rx"], undefined)
  assert.notEqual(cardProperties["--ry"], undefined)
  assert.match(gradientAttributes.gradientTransform, /rotate\(/)
})

test("mount derives the silhouette from fallback SVG without secure-context APIs", (t) => {
  const { controller, sizes } = fixture(t)
  let options
  const original = globalThis.__spectralMarkup
  globalThis.__spectralMarkup = (value) => {
    options = value
    return { html: '<div class="geo-stage"></div>', accent: "#fff" }
  }
  t.after(() => {
    if (original) globalThis.__spectralMarkup = original
    else delete globalThis.__spectralMarkup
  })

  controller.mount()

  assert.deepEqual(options.silhouette, {
    viewbox: "0 0 10 10",
    path: "M0 0L10 0L10 10Z",
  })
  assert.match(options.uid, /^sc-/)
  assert.equal(controller.mounted, true)
  assert.equal(sizes.length, 1)
})

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

test("a fresh controller adopts material restored from the Turbo cache", (t) => {
  const { controller, intersections, sizes } = fixture(t, {
    restoredMaterial: true,
  })
  let renders = 0
  const original = globalThis.__spectralMarkup
  globalThis.__spectralMarkup = () => {
    renders += 1
  }
  t.after(() => {
    if (original) globalThis.__spectralMarkup = original
    else delete globalThis.__spectralMarkup
  })

  controller.connect()
  intersections[0].callback([{ isIntersecting: true }])

  assert.equal(controller.mounted, true)
  assert.equal(renders, 0)
  assert.equal(sizes.length, 1)
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
