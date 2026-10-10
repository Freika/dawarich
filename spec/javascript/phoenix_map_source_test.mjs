import assert from "node:assert/strict"
import { test } from "node:test"
import { createStudioSource } from "../../app-phoenix/assets/js/map/data/studio_source.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
const state = (revision) => ({
  revision,
  title: "Synthetic route",
  range: {
    startAt: "2026-10-01",
    endAt: "2026-10-02",
    importId: 3,
    timezone: "Europe/Berlin",
  },
})

test("studio snapshots require the current owner revision after bounded data resolves", async () => {
  let current = state(1)
  const pending = deferred()
  const source = createStudioSource({
    getState: () => current,
    readSnapshot: () => pending.promise,
  })
  const snapshot = source.snapshot({ purpose: "poster" })
  current = state(2)
  pending.resolve({ points: [{ id: 1 }] })
  await assert.rejects(snapshot, { name: "AbortError" })
  source.destroy()
})

test("studio range application awaits a matching revision and trip ranges stay fixed", async () => {
  let current = state(1)
  let writes = 0
  const source = createStudioSource({
    getState: () => current,
    readSnapshot: async () => ({ points: [{ id: 1 }] }),
    applyDates: async () => {
      writes++
      current = state(2)
      return { revision: 2 }
    },
  })
  assert.deepEqual(await source.applyDates(state(2).range), { revision: 2 })
  const snapshot = await source.snapshot({ purpose: "video" })
  assert.equal(snapshot.revision, 2)
  assert.equal(snapshot.range.timezone, "Europe/Berlin")
  assert.equal(snapshot.points[0].id, 1)
  const trip = createStudioSource({
    getState: () => current,
    readSnapshot: async () => ({ points: [] }),
    fixedRange: true,
    applyDates: () => writes++,
  })
  await assert.rejects(trip.applyDates({}), /fixed/)
  assert.equal(writes, 1)
  trip.destroy()
  source.destroy()
})

test("destroy during a studio snapshot aborts and prevents geometry delivery", async () => {
  const pending = deferred()
  let signal
  const source = createStudioSource({
    getState: () => state(1),
    readSnapshot: (_, options) => {
      signal = options.signal
      return pending.promise
    },
  })
  const snapshot = source.snapshot({ purpose: "poster" })
  source.destroy()
  assert.equal(signal.aborted, true)
  pending.resolve({ points: [{ id: 1 }] })
  await assert.rejects(snapshot, { name: "AbortError" })
})
