import assert from "node:assert/strict"
import { test } from "node:test"
import { ReplayManager } from "../../app-phoenix/assets/js/map/replay/manager.js"
import { createReplayPanel } from "../../app-phoenix/assets/js/map/replay/panel.js"

const point = (timestamp, velocity) => ({
  geometry: { coordinates: [13.4, 52.5] },
  properties: { timestamp, velocity },
})

function control() {
  const listeners = new Map()
  const node = {
    textContent: "",
    value: "0",
    max: "0",
    disabled: false,
    attributes: {},
    hidden: false,
    setAttribute(name, value) {
      node.attributes[name] = value
    },
    removeAttribute(name) {
      delete node.attributes[name]
    },
    addEventListener: (type, fn) => listeners.set(type, fn),
    removeEventListener: (type, fn) =>
      listeners.get(type) === fn && listeners.delete(type),
    fire: (type) => listeners.get(type)?.(),
    listeners,
  }
  return node
}

const translate = (key, vars = {}) => `${key}${JSON.stringify(vars)}`

test("replay panel drives speed, day navigation, scrubber seek and live state", () => {
  const manager = new ReplayManager({ timezone: "UTC" })
  manager.setPoints([
    point("2026-06-01T08:00:00Z", 5),
    point("2026-06-02T09:30:00Z"),
  ])
  const calls = []
  const replay = {
    manager,
    playing: false,
    play() {
      calls.push("play")
      replay.playing = true
    },
    pause() {
      calls.push("pause")
      replay.playing = false
    },
    seek: (minute) => calls.push(["seek", minute]),
    setSpeed: (speed) => calls.push(["speed", speed]),
    recenter: () => calls.push("recenter"),
  }
  const elements = Object.fromEntries(
    [
      "play",
      "speed",
      "speedLabel",
      "prev",
      "next",
      "day",
      "dayCount",
      "time",
      "velocity",
      "noData",
      "follow",
      "scrubber",
    ].map((name) => [name, control()]),
  )
  const panel = createReplayPanel({ elements, replay, translate })

  assert.equal(elements.prev.disabled, true)
  assert.equal(elements.next.disabled, false)
  assert.equal(elements.scrubber.max, "1439")
  assert.match(elements.dayCount.textContent, /"current":1,"total":2/)

  elements.speed.value = "4"
  elements.speed.fire("input")
  assert.equal(elements.speedLabel.textContent, "10x")

  elements.scrubber.value = "600"
  elements.scrubber.fire("input")
  assert.equal(elements.time.textContent, "10:00")
  assert.equal(elements.noData.hidden, false)

  elements.play.fire("click")
  assert.equal(elements.play.attributes["aria-pressed"], "true")
  panel.onState({ minute: 480, point: point("2026-06-01T08:00:00Z", 5) })
  assert.equal(elements.scrubber.value, "480")
  assert.equal(elements.noData.hidden, true)
  assert.match(elements.velocity.textContent, /"speed":18/)

  elements.next.fire("click")
  assert.equal(manager.getCurrentDay(), "2026-06-02")
  assert.equal(elements.prev.disabled, false)
  assert.equal(elements.next.disabled, true)
  assert.equal(elements.play.attributes["aria-pressed"], "false")

  elements.follow.fire("click")
  assert.deepEqual(calls, [
    ["speed", 10],
    ["seek", 600],
    "play",
    "pause",
    ["seek", 570],
    "recenter",
  ])

  panel.destroy()
  for (const element of Object.values(elements))
    assert.equal(element.listeners.size, 0)
})

test("native replay exposes numeric day counters and clears them with its panel owner", () => {
  const manager = new ReplayManager({ timezone: "UTC" })
  manager.setPoints([
    point("2026-06-01T08:00:00Z", 5),
    point("2026-06-02T09:30:00Z", 2),
  ])
  const elements = Object.fromEntries(
    [
      "play",
      "speed",
      "speedLabel",
      "prev",
      "next",
      "day",
      "dayCount",
      "time",
      "velocity",
      "noData",
      "scrubber",
      "follow",
    ].map((name) => [name, control()]),
  )
  const replay = {
    manager,
    pause() {},
    play() {},
    seek() {},
    setSpeed() {},
    recenter() {},
  }
  const panel = createReplayPanel({ elements, replay, translate })
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(elements.dayCount.attributes).filter(([key]) =>
        key.startsWith("data-replay-"),
      ),
    ),
    {
      "data-replay-day-count": "2",
      "data-replay-day-index": "0",
      "data-replay-point-count": "1",
    },
  )
  elements.next.fire("click")
  assert.equal(elements.dayCount.attributes["data-replay-day-index"], "1")
  panel.destroy()
  assert.equal(elements.dayCount.attributes["data-replay-day-count"], undefined)
})

test("timeline-started playback updates the native replay play state", () => {
  const manager = new ReplayManager({ timezone: "UTC" })
  manager.setPoints([point("2026-06-01T08:00:00Z", 5)])
  const elements = Object.fromEntries(
    ["play", "speed", "speedLabel", "prev", "next", "day", "dayCount", "time", "velocity", "noData", "follow", "scrubber"].map((key) => [key, control()]),
  )
  const replay = { manager, playing: false, seek() {}, play() { this.playing = true }, pause() { this.playing = false } }
  const panel = createReplayPanel({ elements, replay, translate })
  replay.play()
  panel.onState({ minute: 480 })
  assert.equal(elements.play.attributes["aria-pressed"], "true")
  replay.pause()
  panel.onState({ minute: 480 })
  assert.equal(elements.play.attributes["aria-pressed"], "false")
  panel.destroy()
})

test("closing the native replay panel clears its play state before reopening", () => {
  const manager = new ReplayManager({ timezone: "UTC" })
  manager.setPoints([point("2026-06-01T08:00:00Z", 5)])
  const elements = Object.fromEntries(
    ["play", "speed", "speedLabel", "prev", "next", "day", "dayCount", "time", "velocity", "noData", "follow", "scrubber"].map((key) => [key, control()]),
  )
  const replay = { manager, playing: true, seek() {} }
  const panel = createReplayPanel({ elements, replay, translate })
  panel.onState({ minute: 480 })
  assert.equal(elements.play.attributes["aria-pressed"], "true")
  panel.destroy()
  assert.equal(elements.play.attributes["aria-pressed"], "false")
})
