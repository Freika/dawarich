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
