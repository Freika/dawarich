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

const startupSource = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/map_startup.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const startup = await import(
  `data:text/javascript;base64,${Buffer.from(`
    const MapInitializer = {
      initialize: (...args) => globalThis.__webglTestInitialize(...args),
    }
    const loadLastView = () => null
    const saveView = () => {}
    const syncSidebarLayout = () => {}
    ${startupSource}
  `).toString("base64")}`
)

function buildController(initialize) {
  globalThis.__webglTestInitialize = initialize
  const controller = {
    settings: {},
    webglErrorShown: false,
    containerTarget: { classList: { add() {} } },
    webglErrorTarget: {
      classList: {
        remove: () => {
          controller.webglErrorShown = true
        },
      },
    },
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
  const controller = buildController(async () => {
    throw new GPUInitializationError()
  })

  await startup.initializeMap(controller)

  assert.equal(controller.webglErrorShown, true)
  assert.equal(controller.map, undefined)
})

test("rethrows map initialization errors that are not about the GPU", async () => {
  const controller = buildController(async () => {
    throw new Error("style failed")
  })

  await assert.rejects(startup.initializeMap(controller), /style failed/)
  assert.equal(controller.webglErrorShown, false)
})

const disconnectStart = source.indexOf("  disconnect() {")
const disconnectSource = source.slice(
  disconnectStart,
  source.indexOf("\n  }\n", disconnectStart) + 4,
)

async function buildLifecycleController() {
  const moduleSource = `
    const cancelAllPreviews = () => {}
    const performanceMonitor = { logReport: () => {} }
    export default class {
      ${disconnectSource}
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
  assert.equal(startup.isWebGLSupported(), true)
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
  assert.equal(startup.isWebGLSupported(), false)
})
