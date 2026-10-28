import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/editing/place_panel_bridge.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const stubs = `
  const calls = { push: (call) => globalThis.__bridgeCalls.push(call) }
  const removePlaceFeature = () => {}
  const consumePlaceParams = () => null
  const shouldCenterPlace = () => true
  class PlaceGeometryEditor { stop() {} start() {} }
  class PlaceCamera { fit(place) { calls.push(["fit", place.id]) } cancel() {} }
  class SelectedPlaceLayer {
    show(place) {
      calls.push(["show", place.id])
      globalThis.__selectedPlace = place.id
    }
    clear() { globalThis.__selectedPlace = null }
    destroy() {}
  }
`
const { PlacePanelBridge } = await import(
  `data:text/javascript;base64,${Buffer.from(stubs + source).toString("base64")}`
)

const handlers = {}
globalThis.CustomEvent ??= class CustomEvent extends Event {
  constructor(type, options = {}) {
    super(type, options)
    this.detail = options.detail ?? null
  }
}
globalThis.document = { dispatchEvent() {} }
globalThis.window = { location: { href: "http://localhost/map/v2" } }

function bridge() {
  globalThis.__bridgeCalls = []
  return new PlacePanelBridge({
    map: {},
    closeInfo: () => globalThis.__bridgeCalls.push(["closeInfo"]),
    cleanup: {
      addEventListener: (_target, type, handler) => {
        handlers[type] = handler
      },
    },
  })
}

test("a loaded place is highlighted and centred", () => {
  const panel = bridge()
  panel.open(7)
  panel.loaded({ id: 7 })
  assert.deepEqual(globalThis.__bridgeCalls, [
    ["closeInfo"],
    ["show", 7],
    ["fit", 7],
  ])
})

test("a place hidden by a privacy zone is neither highlighted nor centred", () => {
  const panel = bridge()
  panel.open(7)
  panel.loaded({ id: 7, privacy_hidden: true })
  handlers["place:map-cancel"]()
  assert.deepEqual(globalThis.__bridgeCalls, [["closeInfo"]])
})

test("clicking the place that is already open does not reload its panel", () => {
  const opened = []
  globalThis.document = { dispatchEvent: (event) => opened.push(event.type) }
  const panel = bridge()
  panel.open(7)
  panel.open("7")
  panel.open(7, true)
  assert.deepEqual(opened, ["place:open", "place:open"])
  globalThis.document = { dispatchEvent() {} }
})

test("a place that becomes hidden loses its highlight", () => {
  const panel = bridge()
  panel.open(7)
  panel.loaded({ id: 7 })
  assert.equal(globalThis.__selectedPlace, 7)
  panel.loaded({ id: 7, privacy_hidden: true })
  assert.equal(globalThis.__selectedPlace, null)
})
