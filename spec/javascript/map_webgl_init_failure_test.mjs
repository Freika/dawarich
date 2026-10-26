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
