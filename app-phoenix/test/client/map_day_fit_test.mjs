import assert from "node:assert/strict"
import test from "node:test"
import { MapHook } from "../../assets/js/map/hooks/map.js"

function mount() {
  const handlers = {}
  const fits = []
  const hook = Object.assign(Object.create(MapHook), {
    el: { dataset: {}, classList: { toggle() {} } },
    handleEvent: (name, callback) => {
      handlers[name] = callback
      return name
    },
    removeHandleEvent() {},
    pushEvent() {},
    loader: () => new Promise(() => {}),
  })
  hook.mounted()
  hook.mapOwner = { map: { fitBounds: (...args) => fits.push(args) }, destroy() {} }
  return { hook, handlers, fits }
}

const bounds = { sw_lat: 52.5, sw_lng: 13.39, ne_lat: 52.53, ne_lng: 13.42 }

test("a settled timeline day fits the ready map like the Rails day frame", () => {
  const { hook, handlers, fits } = mount()
  hook.mapReady = true
  handlers["timeline:fit"]({ bounds })
  assert.deepEqual(fits, [
    [
      [
        [13.39, 52.5],
        [13.42, 52.53],
      ],
      { padding: 60, duration: 500 },
    ],
  ])
  handlers["timeline:fit"]({ bounds: { ...bounds, ne_lat: "x" } })
  assert.equal(fits.length, 1)
  hook.destroyed()
})

test("a day fit that arrives before the map is ready waits for it", () => {
  const { hook, handlers, fits } = mount()
  handlers["timeline:fit"]({ bounds })
  assert.equal(fits.length, 0)
  assert.deepEqual(hook.mapDayFit, [
    [13.39, 52.5],
    [13.42, 52.53],
  ])
  hook.destroyed()
})
