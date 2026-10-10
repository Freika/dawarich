import assert from "node:assert/strict"
import { test } from "node:test"
import { createFollowCamera } from "../../app-phoenix/assets/js/map/replay/follow.js"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"
import {
  createStepper,
  segmentDurationMs,
  speedFromSlider,
} from "../../app-phoenix/assets/js/map/replay/playback.js"
import { createScrubber } from "../../app-phoenix/assets/js/map/replay/scrubber.js"

const point = (timestamp, lon, lat = 52.5) => ({
  geometry: { coordinates: [lon, lat] },
  properties: { timestamp },
})

test("playback interpolates between points with Rails segment timing and rolls into the next day", () => {
  assert.equal(segmentDurationMs(1_000, 61_000, 2), 500)
  assert.equal(segmentDurationMs(1_000, 2_000, 2), 50)
  assert.equal(segmentDurationMs(1_000, 3_601_000, 1), 4000)
  assert.equal(segmentDurationMs(5, 5, 2), 250)
  assert.equal(speedFromSlider("3"), 5)
  assert.equal(speedFromSlider("9"), 2)

  const manager = new ReplayManager({ timezone: "UTC" })
  manager.setPoints([
    point("2026-06-01T08:00:00Z", 13.0),
    point("2026-06-01T08:01:00Z", 14.0),
    point("2026-06-01T09:00:00Z", 15.0),
    point("2026-06-02T07:00:00Z", 16.0),
  ])
  const stepper = createStepper({ manager, speed: 2 })
  const first = stepper.start(480, 1000)
  assert.deepEqual(manager.getCoordinates(first), { lon: 13, lat: 52.5 })

  const half = stepper.frame(1250)
  assert.equal(half.coords.lon, 13.5)
  assert.equal(half.point, null)

  const stepped = stepper.frame(1500)
  assert.equal(stepped.coords.lon, 14)
  assert.equal(stepped.minute, 481)
  assert.deepEqual(manager.getCoordinates(stepped.point), {
    lon: 14,
    lat: 52.5,
  })

  stepper.setSpeed(10, 3500)
  assert.equal(stepper.frame(3500 + 1999).point, null)
  assert.equal(stepper.frame(3500 + 2000).point.geometry.coordinates[0], 15)
  const rolled = stepper.frame(5500 + 50)
  assert.equal(rolled.dayChanged, true)
  assert.equal(manager.getCurrentDay(), "2026-06-02")
  assert.equal(rolled.minute, 420)
  assert.equal(stepper.frame(5550 + 50).done, true)
})

function mapMock() {
  const handlers = new Map()
  let center = { lng: 0, lat: 0 }
  const eased = []
  return {
    handlers,
    eased,
    on: (type, fn) => handlers.set(type, fn),
    off: (type, fn) => handlers.get(type) === fn && handlers.delete(type),
    getCenter: () => center,
    setCenter: ([lng, lat]) => {
      center = { lng, lat }
    },
    getBounds: () => ({
      getEast: () => center.lng + 1,
      getWest: () => center.lng - 1,
      getNorth: () => center.lat + 1,
      getSouth: () => center.lat - 1,
    }),
    easeTo: (options) => eased.push(options),
  }
}

test("follow camera eases toward the marker, jumps when far and stops after a user pan", () => {
  const map = mapMock()
  const states = []
  const follow = createFollowCamera({ map, onChange: (on) => states.push(on) })
  follow.start()
  follow.panTo(1, 0)
  assert.ok(Math.abs(map.getCenter().lng - 0.08) < 1e-9)
  follow.panTo(10, 0)
  assert.deepEqual(map.getCenter(), { lng: 10, lat: 0 })

  map.handlers.get("wheel")()
  follow.panTo(20, 0)
  assert.deepEqual(map.getCenter(), { lng: 10, lat: 0 })
  assert.deepEqual(states, [true, false])

  follow.recenter([20, 0])
  assert.deepEqual(map.eased, [{ center: [20, 0], duration: 400 }])
  assert.equal(follow.following, true)

  follow.destroy()
  assert.equal(map.handlers.size, 0)
  follow.panTo(30, 0)
  assert.deepEqual(map.getCenter(), { lng: 10, lat: 0 })
})

test("scrubber reports integer minutes, follows the day length and releases its listener", () => {
  const listeners = new Map()
  const input = {
    value: "0",
    max: "0",
    addEventListener: (type, fn) => listeners.set(type, fn),
    removeEventListener: (type, fn) =>
      listeners.get(type) === fn && listeners.delete(type),
  }
  const minutes = []
  const scrubber = createScrubber({ input, onMinute: (m) => minutes.push(m) })
  scrubber.setRange(1500)
  assert.equal(input.max, "1499")
  input.value = "731"
  listeners.get("input")()
  scrubber.set(42)
  assert.equal(input.value, "42")
  assert.deepEqual(minutes, [731])
  scrubber.destroy()
  assert.equal(listeners.size, 0)
})

test("playing replay moves the marker along segments, follows it and stops at the end", async () => {
  const frames = []
  const sources = new Map()
  const camera = mapMock()
  const map = {
    ...camera,
    addSource: (id, source) => sources.set(id, { ...source }),
    getSource: (id) =>
      sources.has(id) && {
        setData: (data) => {
          sources.get(id).data = data
        },
      },
    removeSource: (id) => sources.delete(id),
    addLayer() {},
    getLayer: () => true,
    removeLayer() {},
    on: (type, layer, fn) => camera.on(type, fn || layer),
    off: (type, layer, fn) => camera.off(type, fn || layer),
  }
  const followed = []
  const replay = (await import("../../app-phoenix/assets/js/map/replay/runtime.js")).createReplay({
    map,
    timezone: "UTC",
    loadDay: async () => [
      point("2026-06-01T08:00:00Z", 0.0),
      point("2026-06-01T08:01:00Z", 0.4),
    ],
    raf: (fn) => frames.push(fn),
    cancelRaf() {},
    onFollow: (on) => followed.push(on),
    onStop: () => followed.push("stopped"),
  })
  await replay.open({ startAt: "2026-06-01T00:00", endAt: "2026-06-01T23:59" })
  replay.play()
  frames.shift()(1000)
  frames.shift()(1250)
  const lon = () => sources.get("native-replay-marker").data.geometry.coordinates[0]
  assert.equal(lon(), 0.2)
  assert.ok(camera.getCenter().lng > 0)
  frames.shift()(1500)
  assert.equal(lon(), 0.4)
  frames.shift()(1750)
  assert.equal(replay.playing, false)
  assert.equal(frames.length, 0)
  assert.deepEqual(followed, [true, "stopped"])
  replay.close()
  assert.equal(camera.handlers.size, 0)
})
