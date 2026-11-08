import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/accessible_menu_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}\n//# sourceURL=accessible_menu_controller.js`).toString("base64")}`
const { default: AccessibleMenuController } = await import(moduleUrl)

// Listeners run in the order they were added, capture before bubble, and a
// listener is removed only with the capture flag it was added with, as in the
// browser.
function fakeDocument() {
  const listeners = new Map()
  const phase = (type, options) => `${type}:${options?.capture === true}`
  const dispatch = (key, event) => {
    for (const listener of [...(listeners.get(key) || [])]) listener(event)
  }
  return {
    activeElement: null,
    addEventListener(type, listener, options) {
      const key = phase(type, options)
      if (!listeners.has(key)) listeners.set(key, new Set())
      listeners.get(key).add(listener)
    },
    removeEventListener(type, listener, options) {
      listeners.get(phase(type, options))?.delete(listener)
    },
    click(target, { propagationStopped = false } = {}) {
      dispatch("click:true", { target })
      if (!propagationStopped) dispatch("click:false", { target })
    },
    press(key, { defaultPrevented = false } = {}) {
      dispatch("keydown:true", { key, defaultPrevented })
      dispatch("keydown:false", { key, defaultPrevented })
    },
  }
}

// A <details> menu with a summary and one item. Setting open dispatches
// toggle the way the browser does, which the menu's data-action wires to
// sync(). A submenu, when given, is nested inside the menu.
function menu({ submenu = null } = {}) {
  const summary = {
    attributes: {},
    focused: 0,
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    focus() {
      this.focused += 1
      document.activeElement = this
    },
  }
  const item = {}
  const element = {
    summary,
    item,
    isOpen: false,
    controller: null,
    get open() {
      return this.isOpen
    },
    set open(value) {
      this.isOpen = value
      this.controller?.sync()
    },
    contains(node) {
      return (
        node === this ||
        node === summary ||
        node === item ||
        !!submenu?.contains(node)
      )
    },
    querySelector(selector) {
      if (selector === ":scope > summary") return summary
      if (selector === "details[open]") return submenu?.open ? submenu : null
      return null
    },
  }
  const controller = new AccessibleMenuController()
  controller.element = element
  element.controller = controller
  controller.connect()
  return element
}

test("closes an open menu when a click lands outside it", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true

  document.click({})

  assert.equal(navMenu.open, false)
  assert.equal(navMenu.summary.attributes["aria-expanded"], "false")
})

test("closes when the clicked element stops the click reaching document", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true

  document.click({}, { propagationStopped: true })

  assert.equal(navMenu.open, false)
})

test("stays open for clicks inside the menu", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true

  document.click(navMenu.item)
  document.click(navMenu.summary)

  assert.equal(navMenu.open, true)
  assert.equal(navMenu.summary.attributes["aria-expanded"], "true")
})

test("closes on Escape and hands focus back to the menu button", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true
  document.activeElement = navMenu.item

  document.press("Escape")

  assert.equal(navMenu.open, false)
  assert.equal(navMenu.summary.focused, 1)
})

test("does not take focus when Escape is pressed elsewhere on the page", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true
  document.activeElement = {}

  document.press("Escape")

  assert.equal(navMenu.open, false)
  assert.equal(navMenu.summary.focused, 0)
})

test("leaves the menu alone when another overlay already handled Escape", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true
  document.activeElement = navMenu.item

  document.press("Escape", { defaultPrevented: true })

  assert.equal(navMenu.open, true)
  assert.equal(navMenu.summary.focused, 0)
})

test("ignores other keys", () => {
  globalThis.document = fakeDocument()
  const navMenu = menu()
  navMenu.open = true

  document.press("Enter")

  assert.equal(navMenu.open, true)
})

test("closes an open submenu before the menu around it", () => {
  globalThis.document = fakeDocument()
  const submenu = menu()
  const navMenu = menu({ submenu })
  navMenu.open = true
  submenu.open = true

  document.press("Escape")

  assert.equal(submenu.open, false)
  assert.equal(navMenu.open, true)

  document.press("Escape")

  assert.equal(navMenu.open, false)
})

test("stops listening once the menu is closed or leaves the page", () => {
  globalThis.document = fakeDocument()
  const closed = menu()
  closed.open = true
  closed.open = false
  const removed = menu()
  removed.open = true
  removed.controller.disconnect()

  document.click({})
  document.press("Escape")

  assert.equal(closed.open, false)
  assert.equal(removed.open, true)
})
