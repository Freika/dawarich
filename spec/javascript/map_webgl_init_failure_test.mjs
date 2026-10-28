import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/maps/maplibre_controller.js",
    import.meta.url,
  ),
  "utf8",
)

const start = source.indexOf("  async initializeMap() {")
const end = source.indexOf("  /**\n   * Initialize API client", start)
const initializeMapSource = source.slice(start, end)

async function buildController(initialize) {
  globalThis.__webglTestMapInitializer = { initialize }
  const moduleSource = `
    const MapInitializer = globalThis.__webglTestMapInitializer
    const loadLastView = () => null
    const saveView = () => {}
    const syncSidebarLayout = () => {}
    export default class {
      ${initializeMapSource}
    }
  `
  const { default: Controller } = await import(
    `data:text/javascript;base64,${Buffer.from(moduleSource).toString("base64")}#${Math.random()}`
  )
  const controller = new Controller()
  controller.settings = {}
  controller.webglErrorShown = false
  controller.showWebGLError = () => {
    controller.webglErrorShown = true
  }
  return controller
}

class GPUInitializationError extends Error {
  constructor() {
    super("Failed to initialize WebGL")
    this.name = "GPUInitializationError"
  }
}

test("shows the WebGL error instead of throwing when the GPU context cannot be created", async () => {
  const controller = await buildController(async () => {
    throw new GPUInitializationError()
  })

  await controller.initializeMap()

  assert.equal(controller.webglErrorShown, true)
  assert.equal(controller.map, undefined)
})

test("rethrows map initialization errors that are not about the GPU", async () => {
  const controller = await buildController(async () => {
    throw new Error("style failed")
  })

  await assert.rejects(controller.initializeMap(), /style failed/)
  assert.equal(controller.webglErrorShown, false)
})

const lifecycleStart = source.indexOf("  disconnect() {")
const lifecycleEnd = source.indexOf(
  "  /**\n   * Initialize MapLibre map",
  lifecycleStart,
)
const lifecycleSource = source.slice(lifecycleStart, lifecycleEnd)

async function buildLifecycleController() {
  const moduleSource = `
    const cancelAllPreviews = () => {}
    const performanceMonitor = { logReport: () => {} }
    export default class {
      ${lifecycleSource}
    }
  `
  const { default: Controller } = await import(
    `data:text/javascript;base64,${Buffer.from(moduleSource).toString("base64")}#${Math.random()}`
  )
  return new Controller()
}

test("the WebGL probe releases its context instead of holding it until GC", async (t) => {
  const originalDocument = globalThis.document
  t.after(() => {
    globalThis.document = originalDocument
  })
  let released = false
  globalThis.document = {
    createElement: () => ({
      getContext: () => ({
        getExtension: (name) =>
          name === "WEBGL_lose_context"
            ? {
                loseContext: () => {
                  released = true
                },
              }
            : null,
      }),
    }),
  }
  const controller = await buildLifecycleController()

  assert.equal(controller.isWebGLSupported(), true)
  assert.equal(released, true)
})

test("disconnect does not throw when the WebGL probe failed before setup", async () => {
  const controller = await buildLifecycleController()

  assert.doesNotThrow(() => controller.disconnect())
})

test("the WebGL probe reports no support when the browser gives no context", async (t) => {
  const originalDocument = globalThis.document
  t.after(() => {
    globalThis.document = originalDocument
  })
  globalThis.document = {
    createElement: () => ({ getContext: () => null }),
  }
  const controller = await buildLifecycleController()

  assert.equal(controller.isWebGLSupported(), false)
})
