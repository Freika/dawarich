import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const shellSource = await readFile(new URL("../../priv/static/js/map_shell.js", import.meta.url), "utf8")
const realtimeSource = await readFile(new URL("../../../app/javascript/controllers/maps/maplibre_realtime_controller.js", import.meta.url), "utf8")
const channelSource = await readFile(new URL("../../../app/javascript/maps_maplibre/channels/map_channel.js", import.meta.url), "utf8")
const stripImports = (source) => source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "").replace(/^import "[^"]+"\n/gm, "")

function runtime() {
  const timers = new Map()
  const created = []
  const late = []
  const refreshes = []
  const studiosDisconnected = []
  let timerId = 0
  const document = {
    body: { appendChild() {} },
    addEventListener() {},
    dispatchEvent(event) { refreshes.push(event.type) },
    querySelector() { return { dataset: { familyMembersFeaturesValue: '{"family":true}' } } },
  }
  const layers = new Map(["points-mvt", "tracks-mvt", "map-editor", "family"].map((name) => [name, {
    refresh() { refreshes.push(name) },
    applyRealtime(data) { refreshes.push(data.point_id) },
    reapplyTileFilters() {},
    updateMember(member) { refreshes.push(member.user_id) },
  }]))
  const maps = {
    mapDataManager: { invalidatePoints() { refreshes.push("points-invalidated") } },
    layerManager: { getLayer(name) { return layers.get(name) } },
  }
  const consumer = { subscriptions: { create(name, callbacks) {
    const subscription = { name, callbacks, unsubscribes: 0, unsubscribe() { this.unsubscribes++ } }
    created.push(subscription)
    return subscription
  } } }
  class Application {
    constructor(element) { this.element = element; this.controllers = new Map() }
    start() { return Promise.resolve() }
    stop() {}
    register(identifier, Controller) {
      const controller = new Controller()
      Object.assign(controller, { application: this, element: this.element, enabledValue: true, liveModeValue: true })
      this.controllers.set(identifier, controller)
      controller.connect?.()
    }
    unload(identifiers) {
      for (const id of identifiers) {
        this.controllers.get(id)?.disconnect?.()
        this.controllers.delete(id)
      }
    }
    getControllerForElementAndIdentifier(_element, id) {
      return id === "maps--maplibre" ? maps : this.controllers.get(id)
    }
  }
  const globals = {
    document, consumer, Application, Controller: class {},
    window: { Turbo: { session: {} } },
    setTimeout(callback) { const id = ++timerId; timers.set(id, callback); return id },
    clearTimeout(id) { timers.delete(id) },
    console: { log() {}, warn() {}, error() {} },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail } },
    translate: (key) => key, Toast: { success() {}, warning() {}, info() {} },
    SettingsManager: {}, appendRailsFlash() {},
    handleNewPoint(_controller, point) { refreshes.push(point) },
    refreshLiveLayers() {}, updateRecentPoint() {}, zoomToPoint() {},
  }
  const context = vm.createContext(globals)
  vm.runInContext(stripImports(channelSource).replace(/export /g, ""), context)
  vm.runInContext(stripImports(realtimeSource).replace("export default class", "globalThis.Realtime = class"), context)
  globals.lazyLoadControllersFrom = (_path, application, element) => {
    if (element.id === "map-shell") application.register("maps--maplibre-realtime", globals.Realtime)
    else application.register(element.id, class {
      disconnect() { studiosDisconnected.push(element.id) }
    })
    late.push(() => application.register("late-setup", globals.Realtime))
  }
  vm.runInContext(stripImports(shellSource).replace(/export /g, "") + "\nglobalThis.shell = {mount, unmount, join, leave}", context)
  return { shell: globals.shell, created, refreshes, studiosDisconnected, late,
    tick() { const ready = [...timers.values()]; timers.clear(); for (const callback of ready) callback() } }
}

function element(id, studios = []) {
  return { id, isConnected: true, getAttribute() { return "" }, setAttribute() {},
    querySelectorAll() { return studios }, remove() { this.isConnected = false } }
}

test("M07: map presentation and refresh consumers matches current Rails contract without a native-owner Rails effect", async () => {
  const r = runtime()
  const pending = element("map-shell", [element("poster-studio"), element("video-studio")])
  r.shell.mount(pending)
  r.shell.unmount(pending)
  pending.remove()
  for (const release of r.late.splice(0)) release()
  await Promise.resolve()
  r.tick()
  assert.equal(r.created.length, 0, "destroy cancels pending realtime subscription setup")
  assert.deepEqual(r.studiosDisconnected.sort(), ["poster-studio", "video-studio"])
  assert.equal(r.shell.mount(pending), null)

  const root = element("map-shell", [element("poster-studio"), element("video-studio")])
  const application = r.shell.mount(root)
  assert.equal(r.shell.mount(root), application)
  r.tick()
  assert.deepEqual(r.created.map((s) => s.name).sort(), ["FamilyLocationsChannel", "MapEditsChannel", "PointsChannel", "TracksChannel"])
  const subscriptions = Object.fromEntries(r.created.map((s) => [s.name, s]))
  subscriptions.MapEditsChannel.callbacks.received({ type: "point_moved", data: { point_id: 409, latitude: 51.3397, longitude: 12.3731 } })
  assert.deepEqual(r.refreshes.slice(0, 5), ["points-invalidated", 409, "points-mvt", "tracks-mvt", "dawarich:point-moved"])
  subscriptions.TracksChannel.callbacks.received({ action: "geojson_updated", track_id: 409 })
  subscriptions.TracksChannel.callbacks.received({ action: "track_created", track: { id: 410 } })
  r.tick()
  assert.equal(r.refreshes.filter((name) => name === "tracks-mvt").length, 2)
  const hook = { el: root }
  r.shell.join(hook)
  r.shell.leave(hook)
  assert.equal(r.shell.mount(root), application)
  assert.equal(r.created.length, 4)
  r.shell.unmount(root)
  r.shell.unmount(root)
  assert.ok(r.created.every((s) => s.unsubscribes === 1))
  for (const release of r.late.splice(0)) release()
  r.tick()
  assert.equal(r.created.length, 4)
})
