import assert from "node:assert/strict"
import test from "node:test"
import { PublicReplay } from "../../app-phoenix/assets/js/map/shared/shared_replay.js"

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

test("maximum snapshots build bounded formatter and minute indexes with constant frame visits and replace cleared zone caches", () => {
  const original = Intl.DateTimeFormat
  const formats = new Map()
  let constructions = 0
  Intl.DateTimeFormat = class {
    constructor(...args) {
      constructions++
      const key = JSON.stringify(args)
      if (!formats.has(key)) formats.set(key, new original(...args))
      this.formatter = formats.get(key)
    }
    format(...args) {
      return this.formatter.format(...args)
    }
    formatToParts(...args) {
      return this.formatter.formatToParts(...args)
    }
  }

  let visits = 0
  const at = Date.parse("2026-05-10T10:00:00Z") / 1000
  const points = Array.from(
    { length: 10000 },
    (_, id) =>
      new Proxy([id, 51, at + id * 2], {
        get(target, key) {
          if (key === "2") visits++
          return Reflect.get(target, key)
        },
      }),
  )
  try {
    const { view, target } = replay(points)
    assert.ok(constructions <= 4, `constructed ${constructions} formatters`)
    const built = constructions
    visits = 0
    view.draw()
    view.action("replayScrubberHover", "900")
    view.action("replayCycleNext")
    view.action("replayCyclePrev")
    assert.ok(visits <= 16, `visited ${visits} samples after indexing`)
    assert.equal(constructions, built)
    assert.equal(target("replayPointCounter").textContent, "1 / 30")
    const clock = view.clock
    view.clear()
    assert.equal(clock.bounds.size, 0)
    assert.equal(clock.labels.size, 0)
    assert.equal(clock.formats, null)
    assert.deepEqual(view.days, [])
    const replacement = replay(
      [point(1, "2026-05-10T10:00:00Z")],
      "America/New_York",
    )
    assert.equal(replacement.target("replayTimeDisplay").textContent, "06:00")
    assert.notEqual(replacement.view.clock, clock)
    replacement.view.clear()
  } finally {
    Intl.DateTimeFormat = original
  }
})
