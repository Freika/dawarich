import assert from "node:assert/strict"
import test from "node:test"
import { PublicReplay } from "../../app-phoenix/assets/js/hooks/shared_replay.js"

function replay(points, zone = "Europe/Berlin") {
  const targets = new Map()
  const root = {
    querySelector(selector) {
      if (!targets.has(selector))
        targets.set(selector, {
          hidden: true,
          value: "",
          textContent: "",
          classList: { toggle() {} },
        })
      return targets.get(selector)
    },
  }
  class Marker {
    setLngLat(value) {
      this.coordinate = value
      return this
    }
    addTo() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  const view = new PublicReplay(
    root,
    { easeTo() {} },
    { Marker },
    points,
    zone,
    "de",
  )
  const target = (name) =>
    root.querySelector(`[data-public-replay-target="${name}"]`)
  view.action("toggleReplay")
  return { view, target }
}
const point = (id, stamp) => [id, 51, Date.parse(stamp) / 1000]

test("spring replay uses the owner's 23-hour elapsed day and skips the missing hour", () => {
  const { view, target } = replay([
    point(1, "2026-03-29T00:30:00Z"),
    point(2, "2026-03-29T01:30:00Z"),
    point(3, "2026-03-29T21:59:00Z"),
  ])
  assert.equal(Number(target("replayScrubber").max), 1379)
  view.action("replayScrubberHover", "150")
  assert.equal(view.marker.coordinate[0], 2)
  assert.equal(target("replayTimeDisplay").textContent, "03:30")
  view.action("replayScrubberHover", "1379")
  assert.equal(view.marker.coordinate[0], 3)
  assert.equal(target("replayTimeDisplay").textContent, "23:59")
  view.clear()
})

test("autumn replay independently selects both repeated hours with intervening samples and distinct zone labels", () => {
  const { view, target } = replay([
    point(1, "2026-10-25T00:30:00Z"),
    point(2, "2026-10-25T00:45:00Z"),
    point(3, "2026-10-25T01:15:00Z"),
    point(4, "2026-10-25T01:30:00Z"),
    point(5, "2026-10-25T01:30:30Z"),
    point(6, "2026-10-25T22:59:00Z"),
  ])
  assert.equal(Number(target("replayScrubber").max), 1499)
  view.action("replayScrubberHover", "150")
  assert.equal(view.marker.coordinate[0], 1)
  const first = target("replayTimeDisplay").textContent
  assert.match(first, /^02:30 .+/)
  view.action("replayScrubberHover", "210")
  assert.equal(view.marker.coordinate[0], 4)
  assert.match(target("replayTimeDisplay").textContent, /^02:30 .+/)
  assert.notEqual(target("replayTimeDisplay").textContent, first)
  view.action("replayCycleNext")
  assert.equal(view.marker.coordinate[0], 5)
  assert.equal(target("replayPointCounter").textContent, "2 / 2")
  view.action("replayCyclePrev")
  assert.equal(view.marker.coordinate[0], 4)
  view.clear()
})
