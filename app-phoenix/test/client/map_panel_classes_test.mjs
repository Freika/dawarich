import assert from "node:assert/strict"
import test from "node:test"
import { MapHook } from "../../assets/js/map/hooks/map.js"

test("the map host mirrors the open panel as the Rails container classes", () => {
  const classes = new Set(["maps-maplibre-container"])
  const handlers = {}
  const hook = Object.assign(Object.create(MapHook), {
    el: {
      dataset: {},
      classList: {
        toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
      },
    },
    handleEvent: (name, callback) => {
      handlers[name] = callback
      return name
    },
    removeHandleEvent() {},
    pushEvent() {},
    loader: () => new Promise(() => {}),
  })
  hook.mounted()

  handlers["map:config"]({ panel: "layers" })
  assert.deepEqual([...classes].sort(), [
    "maps-maplibre-container",
    "panel-open",
  ])

  handlers["map:config"]({ panel: "timeline" })
  assert.deepEqual([...classes].sort(), [
    "maps-maplibre-container",
    "panel-open",
    "panel-timeline-expanded",
  ])

  handlers["map:config"]({ panel: "" })
  assert.deepEqual([...classes], ["maps-maplibre-container"])
  hook.destroyed()
})
