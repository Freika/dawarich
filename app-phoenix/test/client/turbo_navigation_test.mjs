import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import vm from "node:vm"

const source = await readFile(new URL("../../priv/static/js/app.js", import.meta.url), "utf8")
const listeners = new Map()
const calls = []
let page = "initial"
const globals = {
  Socket: class {},
  LiveSocket: class {
    connect() { calls.push(`connect:${page}`) }
    disconnect() { calls.push(`disconnect:${page}`) }
    destroyAllViews() { calls.push(`destroy:${page}`) }
  },
  MapShell: {}, RailsStimulus: {}, FamilyPage: {}, VideoStudio: {}, meta: () => null,
  bootRailsBridges: () => calls.push(`boot:${page}`),
  stopRailsBridges: () => calls.push(`stop:${page}`),
  bootTurboFrames() {}, watchFlashes() {},
  document: {
    readyState: "complete",
    addEventListener(name, listener) {
      const registered = listeners.get(name) || []
      registered.push(listener)
      listeners.set(name, registered)
    },
    querySelectorAll: () => [],
  },
  window: { addEventListener() {}, setTimeout() {} },
}
vm.runInNewContext(source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, ""), globals)
const emit = (name) => {
  for (const listener of listeners.get(name) || []) listener({ detail: {} })
}
for (const destination of ["empty-range", "changed-range", "tracks", "replay", "video", "digest"]) {
  emit("turbo:before-render")
  const previous = page
  page = destination
  emit("turbo:load")
  assert.ok(calls.includes(`stop:${previous}`), `dispose ${previous}`)
  assert.ok(calls.includes(`destroy:${previous}`), `destroy old LiveView ${previous}`)
  assert.ok(calls.includes(`boot:${destination}`), `boot ${destination}`)
  assert.ok(calls.includes(`connect:${destination}`), `join ${destination}`)
}
emit("turbo:before-cache")
assert.ok(calls.includes("stop:digest"), "cached snapshots cannot retain mounted bridges")
console.log("Turbo map and digest lifecycle passed")

const bridgeSource = await readFile(new URL("../../priv/static/js/rails_bridge.js", import.meta.url), "utf8")
const disposed = []
let roots
const root = (id) => ({
  id, addEventListener() {}, removeEventListener() {}, removeAttribute() {},
  getAttribute: () => "", querySelectorAll: () => [],
})
roots = { form: root("old-form"), map: root("old-map") }
const context = vm.createContext({
  window: {},
  document: {
    addEventListener() {}, removeEventListener() {},
    querySelectorAll: (selector) => selector.includes("RailsStimulus") ? [roots.form] : [roots.map],
  },
})
const dependency = new vm.SyntheticModule(["Application", "lazyLoadControllersFrom", "mount", "unmount"], function () {
  this.setExport("Application", class {
    constructor(element) { this.element = element; this.controllers = [{ identifier: "stat-page" }] }
    async start() {}
    register() {}
    unload(identifiers) { disposed.push([this.element.id, ...identifiers]) }
    stop() { disposed.push([this.element.id, "stop"]) }
  })
  this.setExport("lazyLoadControllersFrom", () => {})
  this.setExport("mount", (element) => disposed.push([element.id, "mount"]))
  this.setExport("unmount", (element) => disposed.push([element.id, "unmount"]))
}, { context })
await dependency.link(() => {})
await dependency.evaluate()
const bridgeModule = new vm.SourceTextModule(bridgeSource, {
  context, importModuleDynamically: () => dependency,
})
await bridgeModule.link(() => {})
await bridgeModule.evaluate()
bridgeModule.namespace.bootRailsBridges()
await bridgeModule.namespace.railsBridge(roots.form).ready
bridgeModule.namespace.stopRailsBridges()
await Promise.resolve()
assert.ok(disposed.some(([id, action]) => id === "old-form" && action === "stat-page"))
assert.ok(disposed.some(([id, action]) => id === "old-map" && action === "unmount"))
assert.equal(context.window.StimulusIslands.size, 0)
roots = { form: root("new-form"), map: root("new-map") }
bridgeModule.namespace.bootRailsBridges()
await bridgeModule.namespace.railsBridge(roots.form).ready
assert.equal(context.window.StimulusIslands.size, 1)
assert.ok(disposed.some(([id, action]) => id === "new-map" && action === "mount"))
bridgeModule.namespace.stopRailsBridges()
console.log("Retained bridge controller disposal and remount passed")
