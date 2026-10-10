import assert from "node:assert/strict"
import { test } from "node:test"
import { createRangeRequests } from "../../app-phoenix/assets/js/map/ui/navigation.js"

function fixture() {
  const pushed = []
  const timers = new Map()
  let next = 0
  const requests = createRangeRequests({
    pushEvent: (event, payload, reply) =>
      pushed.push({ event, payload, reply }),
    timers: {
      setTimeout: (fn) => {
        next += 1
        timers.set(next, fn)
        return next
      },
      clearTimeout: (id) => timers.delete(id),
    },
    timeoutMs: 1000,
  })
  return { pushed, timers, requests }
}

const range = (day) => ({ startAt: `${day}T00:00`, endAt: `${day}T23:59` })

test("rapid date patches cannot apply old map data", async () => {
  const { pushed, timers, requests } = fixture()
  const first = requests.applyDates(range("2026-04-01"))
  const second = requests.applyDates(range("2026-04-02"))
  await assert.rejects(first, { name: "AbortError" })
  assert.deepEqual(
    pushed.map(({ event, payload }) => [event, payload.startAt]),
    [
      ["map:range", "2026-04-01T00:00"],
      ["map:range", "2026-04-02T00:00"],
    ],
  )

  pushed[0].reply({ revision: 2 })
  pushed[1].reply({ revision: 3 })
  let settled = false
  second.then(() => {
    settled = true
  })
  requests.config({ revision: 2 })
  await Promise.resolve()
  assert.equal(settled, false)
  requests.config({ revision: 3, range: { startAt: "x" } })
  assert.deepEqual(await second, { revision: 3 })
  assert.equal(timers.size, 0)
})

test("range acknowledgement handles refusal, early config, timeout and destroy", async () => {
  const { pushed, timers, requests } = fixture()
  const refused = requests.applyDates(range("2026-04-03"))
  pushed[0].reply({ error: "invalid_range" })
  await assert.rejects(refused, /invalid_range/)

  requests.config({ revision: 5 })
  const unchanged = requests.applyDates(range("2026-04-04"))
  pushed[1].reply({ revision: 5 })
  assert.deepEqual(await unchanged, { revision: 5 })

  const slow = requests.applyDates(range("2026-04-05"))
  pushed[2].reply({ revision: 6 })
  for (const fn of [...timers.values()]) fn()
  await assert.rejects(slow, /range_timeout/)

  const pending = requests.applyDates(range("2026-04-06"))
  requests.destroy()
  await assert.rejects(pending, { name: "AbortError" })
  assert.equal(timers.size, 0)
  await assert.rejects(requests.applyDates(range("2026-04-07")), {
    name: "AbortError",
  })

  const controller = new AbortController()
  const fresh = fixture()
  const aborted = fresh.requests.applyDates(range("2026-04-08"), {
    signal: controller.signal,
  })
  controller.abort()
  await assert.rejects(aborted, { name: "AbortError" })
  assert.equal(fresh.timers.size, 0)
})
