import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/map_panel_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(
  `class Controller {}\nconst translate = (key) => key\n${withoutImports}`,
).toString("base64")}`
const { default: MapPanelController } = await import(moduleUrl)

// connect() binds its shortcuts on the document; capture that handler.
function pressKey(
  key,
  { target = null, shiftKey = key === "?", ...mods } = {},
) {
  const listeners = {}
  const dialog = {
    open: false,
    showModal() {
      this.open = true
    },
  }
  globalThis.window = { location: { search: "" } }
  globalThis.document = {
    addEventListener: (name, handler) => {
      listeners[name] = handler
    },
    removeEventListener() {},
    querySelector: () => null,
    getElementById: (id) => (id === "keyboard-shortcuts" ? dialog : null),
  }
  const controller = new MapPanelController()
  controller.connect()
  let prevented = false
  listeners.keydown({
    key,
    shiftKey,
    target: target ?? { matches: () => false },
    preventDefault: () => {
      prevented = true
    },
    ...mods,
  })
  controller.disconnect()
  return { dialog, prevented }
}

test("? opens the list of map shortcuts", () => {
  const { dialog, prevented } = pressKey("?")
  assert.equal(dialog.open, true)
  assert.equal(prevented, true)
})

test("? typed into a field stays in the field", () => {
  const { dialog } = pressKey("?", {
    target: { matches: (selector) => selector.includes("input") },
  })
  assert.equal(dialog.open, false)
})

test("a browser combination with ? stays with the browser", () => {
  const { dialog } = pressKey("?", { metaKey: true })
  assert.equal(dialog.open, false)
})

test("/ typed with Shift, as on German or French layouts, still opens Search", () => {
  const requested = []
  const listeners = {}
  globalThis.window = { location: { search: "" } }
  globalThis.document = {
    addEventListener: (name, handler) => {
      listeners[name] = handler
    },
    removeEventListener() {},
    querySelector: (selector) =>
      selector === '[data-tab-content="search"]' ? {} : null,
    getElementById: () => null,
  }
  const controller = new MapPanelController()
  controller.requestTab = (tab) => requested.push(tab)
  controller.connect()
  listeners.keydown({
    key: "/",
    shiftKey: true,
    target: { matches: () => false },
    preventDefault() {},
  })
  controller.disconnect()
  assert.deepEqual(requested, ["search"])
})
