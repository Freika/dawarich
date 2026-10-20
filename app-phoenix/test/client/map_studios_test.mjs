import assert from "node:assert/strict"
import { test } from "node:test"
import { installStudios } from "../../assets/js/map/ui/studios.js"
import { studioQuery, studioQueryAll, studioValue, studioPanel } from "../../assets/js/studios/dom.js"

test("embedded studio controls resolve native attributes and their values", () => {
  const input = { dataset: { nativeVideoSetting: "duration_sec" } }
  const root = {
    dataset: { nativeStudio: "video" },
    querySelector: (s) => s === "[data-native-video-setting]" ? input : null,
    querySelectorAll: (s) => s === "[data-native-video-setting]" ? [input] : [],
  }
  assert.equal(studioQuery(root, "[data-video-setting]"), input)
  assert.deepEqual(studioQueryAll(root, "[data-video-setting]"), [input])
  assert.equal(studioValue(input, "videoSetting"), "duration_sec")
})

test("embedded studio panels open and close with class state and release Escape", () => {
  const classes = new Set(["hidden"])
  const events = new EventTarget()
  const root = { dataset: { nativeStudio: "poster" }, ownerDocument: events,
    classList: { remove: (c) => classes.delete(c), add: (c) => classes.add(c), contains: (c) => classes.has(c) } }
  const panel = studioPanel(root, null)
  let closed = 0
  const destroy = panel.onCancel(() => { closed++; panel.close() })
  panel.showModal()
  assert.equal(panel.open, true)
  const key = new Event("keydown"); key.key = "Escape"
  events.dispatchEvent(key)
  assert.equal(closed, 1)
  assert.equal(panel.open, false)
  destroy()
  panel.showModal()
  events.dispatchEvent(key)
  assert.equal(closed, 1)
})

test("map studio entry opens Rails panel ids and switches back to poster", () => {
  const opened = [], listeners = new Map()
  const poster = { dispatchEvent: (e) => opened.push(e.type) }
  const video = { dispatchEvent: (e) => opened.push(e.type) }
  const root = { querySelector: (s) => ({ "#poster-studio": poster, "#video-studio": video }[s]),
    addEventListener: (n,f) => listeners.set(n,f), removeEventListener: (n) => listeners.delete(n) }
  const cleanups = [], owner = { source: {} }
  installStudios({ element: { closest: () => root }, owner, lifetime: { own: (f) => cleanups.push(f) } })
  owner.openStudio("video")
  listeners.get("dawarich:studio-switch")({ target: video, detail: { studio: "poster", source: owner.source } })
  assert.deepEqual(opened, ["dawarich:video-studio-open", "dawarich:poster-studio-open"])
  cleanups.reverse().forEach((f) => f())
  assert.equal(listeners.size, 0)
})

test("embedded poster catalogues populate once with localized labels and order sizes", async () => {
  const { populatePosterControls } = await import("../../assets/js/studios/poster_controls.js")
  const make = (tag) => ({ tag, children: [], dataset: {}, append(...items) { this.children.push(...items) }, setAttribute(k,v) { this[k] = v } })
  const nodes = Object.fromEntries(["layout", "font", "size-options"].map((n) => [n, make("select")]))
  const root = { dataset: { nativeStudio: "poster" }, ownerDocument: { createElement: make },
    querySelector: (s) => nodes[/data-native-poster-([^\]]+)/.exec(s)?.[1]] ?? null }
  const config = { controls: { layouts: [{ label: "Drucken", options: [{ value: "print-a3", label: "A3 Hochformat" }] }],
    fonts: [{ value: "oswald", label: "Oswald" }], sizes: [{ value: "print-30x40", label: "30 × 40 cm" }] } }
  populatePosterControls(root, config)
  populatePosterControls(root, config)
  assert.equal(nodes.layout.children.length, 1)
  assert.equal(nodes.layout.children[0].label, "Drucken")
  assert.equal(nodes.layout.children[0].children[0].textContent, "A3 Hochformat")
  assert.equal(nodes.font.children[0].value, "oswald")
  assert.equal(nodes["size-options"].children[0].dataset.nativePosterPrintSize, "print-30x40")
  assert.match(nodes["size-options"].children[0].children[1].textContent, /€44.99/)
})

test("embedded studios enter the browser top layer without leaving their LiveView owner", () => {
  const classes = new Set(["hidden"])
  const calls = []
  const root = {
    classList: { remove: (c) => classes.delete(c), add: (c) => classes.add(c), contains: (c) => classes.has(c) },
    style: {},
    showPopover() { calls.push(["show", this.popover, { ...this.style }, classes.has("hidden")]) },
    hidePopover() { calls.push(["hide", classes.has("hidden")]) },
  }
  const panel = studioPanel(root, null)
  panel.showModal()
  panel.showModal()
  assert.deepEqual(calls, [["show", "manual", { margin: "0", border: "0", padding: "0", width: "100%", height: "100%" }, false]])
  panel.close()
  panel.close()
  assert.deepEqual(calls.at(-1), ["hide", false])
  assert.equal(calls.length, 2)
  assert.equal(panel.open, false)
})


test("embedded studios restore their launcher focus after Escape and discard stale launchers", () => {
  const classes = new Set(["hidden"])
  const events = new EventTarget()
  const focus = []
  const launcher = { isConnected: true, focus: (options) => focus.push(options) }
  events.activeElement = launcher
  const root = {
    ownerDocument: events,
    classList: { remove: (c) => classes.delete(c), add: (c) => classes.add(c), contains: (c) => classes.has(c) },
  }
  const panel = studioPanel(root, null)
  const destroy = panel.onCancel(() => panel.close())
  panel.showModal()
  events.activeElement = { isConnected: true, focus: () => assert.fail("focused a studio control") }
  panel.showModal()
  const escape = new Event("keydown"); escape.key = "Escape"
  events.dispatchEvent(escape)
  assert.equal(panel.open, false)
  assert.deepEqual(focus, [{ preventScroll: true }])
  panel.close()
  assert.equal(focus.length, 1)
  events.activeElement = launcher
  panel.showModal()
  launcher.isConnected = false
  panel.close()
  assert.equal(focus.length, 1)
  destroy()
})
