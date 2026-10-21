import assert from "node:assert/strict"
import test from "node:test"
import { MapHook } from "../../assets/js/map/hooks/map.js"
import { installDayFit } from "../../assets/js/map/ui/day_fit.js"

const bounds = { sw_lat: 52.5, sw_lng: 13.39, ne_lat: 52.53, ne_lng: 13.42 }

function owner() {
  const fits = []
  const cleanups = []
  const value = { map: { fitBounds: (...args) => fits.push(args) } }
  installDayFit({ owner: value, lifetime: { own: (fn) => cleanups.push(fn) } })
  return { value, fits, cleanups }
}

test("a timeline day fits the map like the Rails day frame and ignores bad bounds", () => {
  const { value, fits, cleanups } = owner()
  value.fitDay(bounds)
  value.fitDay({ ...bounds, ne_lat: "x" })
  assert.deepEqual(fits, [
    [
      [
        [13.39, 52.5],
        [13.42, 52.53],
      ],
      { padding: 60, duration: 500 },
    ],
  ])
  for (const fn of cleanups) fn()
  assert.equal(value.fitDay, undefined)
})

test("the map hook holds a day fit until the map is ready", () => {
  const handlers = {}
  const fitted = []
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
  hook.mapOwner = { fitDay: (value) => fitted.push(value), destroy() {} }
  handlers["timeline:fit"]({ bounds })
  assert.deepEqual(fitted, [])
  assert.deepEqual(hook.mapDayFit, bounds)
  hook.mapReady = true
  handlers["timeline:fit"]({ bounds })
  assert.deepEqual(fitted, [bounds])
  hook.destroyed()
})
