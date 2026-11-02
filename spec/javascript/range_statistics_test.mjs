import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/components/range_statistics.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const prelude = `const formatNumber = n => new Intl.NumberFormat('en').format(n);
const translate = (key, values) => values ? JSON.stringify(values) : key;\n`
const { RangeStatistics } = await import(
  `data:text/javascript;base64,${Buffer.from(prelude + source).toString("base64")}`
)
const element = () => ({
  textContent: "",
  attributes: {},
  setAttribute(key, value) {
    this.attributes[key] = value
  },
})

test("km → mi → km converts the original meters without accumulating rounding", async () => {
  const el = element()
  const statistics = new RangeStatistics(el, {
    fetchRangeStatistics: async () => ({
      points: 10,
      distance_meters: 1609.344,
    }),
  })
  await statistics.load("start", "end")
  assert.equal(JSON.parse(el.textContent).distance, "1.61")
  statistics.setUnit("mi")
  assert.equal(JSON.parse(el.textContent).distance, "1")
  statistics.setUnit("km")
  assert.equal(JSON.parse(el.textContent).distance, "1.61")
})

test("zero points is a result; errors clear old totals", async () => {
  const el = element()
  const api = {
    fetchRangeStatistics: async () => ({ points: 0, distance_meters: 0 }),
  }
  const statistics = new RangeStatistics(el, api)
  await statistics.load("start", "end")
  assert.equal(JSON.parse(el.textContent).points, "0")
  api.fetchRangeStatistics = async () => {
    throw new Error("offline")
  }
  await statistics.load("new-start", "new-end")
  assert.equal(el.textContent, "range_statistics.unavailable")
  assert.equal(el.attributes["aria-busy"], "false")
})

test("rapid changes abort the previous request and ignore late responses even if abort is ignored", async () => {
  const pending = []
  const signals = []
  const el = element()
  const statistics = new RangeStatistics(el, {
    fetchRangeStatistics: ({ signal }) => {
      signals.push(signal)
      return new Promise((resolve) => pending.push(resolve))
    },
  })
  const first = statistics.load("first", "first")
  const second = statistics.load("second", "second")
  assert.equal(signals[0].aborted, true)
  pending[1]({ points: 2, distance_meters: 2000 })
  await second
  pending[0]({ points: 1, distance_meters: 1000 })
  await first
  assert.equal(JSON.parse(el.textContent).points, "2")
  const third = statistics.load("third", "third")
  statistics.destroy()
  pending[2]({ points: 3, distance_meters: 3000 })
  await third
  assert.equal(signals[2].aborted, true)
  assert.equal(el.textContent, "common.loading")
})

test("refresh coalesces point invalidations and keeps the selected period", async () => {
  const originalSetTimeout = globalThis.setTimeout
  const originalClearTimeout = globalThis.clearTimeout
  const timers = new Map()
  const requests = []
  let sequence = 0
  globalThis.setTimeout = (callback) => {
    const id = ++sequence
    timers.set(id, callback)
    return id
  }
  globalThis.clearTimeout = (id) => timers.delete(id)
  try {
    const statistics = new RangeStatistics(element(), {
      fetchRangeStatistics: async ({ start_at, end_at }) => {
        requests.push([start_at, end_at])
        return { points: 0, distance_meters: 0 }
      },
    })
    await statistics.load("selected-start", "selected-end")
    statistics.refresh()
    statistics.refresh()
    assert.equal(timers.size, 1)
    await [...timers.values()][0]()
    assert.deepEqual(requests, [
      ["selected-start", "selected-end"],
      ["selected-start", "selected-end"],
    ])
    statistics.refresh()
    statistics.destroy()
    assert.equal(timers.size, 0)
  } finally {
    globalThis.setTimeout = originalSetTimeout
    globalThis.clearTimeout = originalClearTimeout
  }
})
