import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}.js`, import.meta.url), "utf8")
const strip = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { default: PlacePanelController } = await import(
  `data:text/javascript;base64,${Buffer.from(
    `class Controller {}
${await read("maps_maplibre/editing/place_editor_state")}
${strip(await read("controllers/place_panel_controller"))}`,
  ).toString("base64")}`
)

test("opening place details leaves Back unfocused", () => {
  let focused = false
  globalThis.document = { activeElement: {} }
  const panel = {
    classList: { contains: () => true, remove() {} },
    querySelector: (selector) =>
      selector === ".panel-body"
        ? { scrollTop: 0 }
        : { dataset: { tabContent: "layers" } },
  }
  const controller = new PlacePanelController()
  controller.state = { open: false }
  controller.element = {
    closest: () => panel,
    classList: { remove() {} },
    getAttribute: () => "Place details",
  }
  controller.application = {
    getControllerForElementAndIdentifier: () => ({
      openTabByName() {},
      titleTarget: {},
    }),
  }
  controller.frameTarget = {}
  controller.closeTarget = {
    focus: () => {
      focused = true
    },
  }
  controller.open({ id: 2 })
  assert.equal(controller.frameTarget.src, "/places/2?map_panel=1")
  assert.equal(focused, false)
})
