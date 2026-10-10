import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const appSource = await readFile(new URL("../../priv/static/js/app.js", import.meta.url), "utf8")
const liveSource = await readFile(new URL("../../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js", import.meta.url), "utf8")

test("retained trip and family actions join the rendered Turbo destination without a reload", () => {
  const listeners = new Map()
  const joins = []
  const reloads = []
  const location = { href: "https://dawarich.test/trips/101", hostname: "dawarich.test" }
  const storage = { getItem() { return null }, setItem() {}, removeItem() {} }
  let root
  const globals = {
    console,
    document: {
      readyState: "complete",
      createElement() { return {} },
      addEventListener(name, callback) {
        const handlers = listeners.get(name) || []
        handlers.push(callback)
        listeners.set(name, handlers)
      },
      querySelectorAll(selector) { return selector.startsWith("[data-phx-session]") ? [root] : [] },
    },
    window: {
      location, localStorage: storage, sessionStorage: storage,
      addEventListener() {}, setTimeout() {},
    },
    MapShell: {}, RailsStimulus: {}, FamilyPage: {}, VideoStudio: {}, meta: () => "csrf",
    bootRailsBridges() {}, stopRailsBridges() {}, bootTurboFrames() {}, watchFlashes() {},
  }
  location.reload = () => reloads.push(location.href)
  class Socket {
    isConnected() { return false }
    onOpen(callback) { this.open = callback }
    connect() { this.open() }
    disconnect() {}
    off() {}
  }
  globals.Socket = Socket
  const context = vm.createContext(globals)
  vm.runInContext(liveSource.replace(/export \{[\s\S]*?\};/, "globalThis.InstalledLiveSocket = LiveSocket"), context)
  class LiveSocket extends globals.InstalledLiveSocket {
    resetReloadStatus() {}
    bindTopLevelEvents() {}
    joinDeadView() {}
    newRootView(element) {
      const view = {
        href: null,
        setHref(href) { this.href = href },
        join() { joins.push(this.href) },
        isConnected() { return true },
        destroy() {},
      }
      this.roots[element.id] = view
      return view
    }
  }
  globals.LiveSocket = LiveSocket
  const render = (path) => {
    Object.assign(location, { href: `https://dawarich.test${path}`, pathname: path, search: "" })
    root = { id: `root-${path}`, hasAttribute: () => true }
  }
  const emit = (name) => {
    for (const handler of listeners.get(name) || []) handler({ detail: {} })
  }
  render("/trips/101")
  vm.runInContext(appSource.replace(/^import[\s\S]*?from "[^"]+"\n/gm, ""), context)
  for (const path of ["/trips/101/edit", "/trips/101", "/exports", "/family/edit", "/family", "/family/new"]) {
    globals.window.liveSocket.unload()
    emit("turbo:before-cache")
    emit("turbo:before-render")
    render(path)
    emit("turbo:load")
    assert.equal(joins.at(-1), location.href, `LiveView action owner must join ${path}`)
    assert.equal(reloads.length, 0, `Turbo ${path} must preserve its action result and flash`)
    assert.equal(globals.window.liveSocket.isNewLocation(location), false)
  }
})
