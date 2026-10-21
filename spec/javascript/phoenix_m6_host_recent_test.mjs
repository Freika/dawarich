import assert from "node:assert/strict"
import test from "node:test"
import { Toast } from "../../app-phoenix/assets/js/map/ui/toast.js"
import { toastDocument } from "../../app-phoenix/test/client/support/toast_dom.mjs"
import { fixture } from "./support/native_m6_host_fixture.mjs"

const row = { id: 37, latitude: 52.51, longitude: 13.41, timestamp: 1774782000 }
test("native point delivery renders the current range marker only when enabled and fences late reads", async t => {
  globalThis.document = toastDocument()
  Toast.container = null
  const messages = []
  t.mock.method(Toast, "info", message => messages.push(message))
  t.after(() => { delete globalThis.document })
  const f = fixture({ liveEnabled: true, uiLabels: { "messages.new_location_recorded": "New location recorded" } }),
    flights = []
  f.map.flyTo = (value) => flights.push(value)
  f.reader.read = async (resource) => ({
    data: resource === "points" ? [] : {},
  })
  assert.equal(await f.owner.mount(), "ready")
  assert.equal(
    f.sources.get("recent-point-source")?.data.features.length ?? 0,
    0,
  )
  await f.owner.reconnect({ kinds: ["family"] })
  assert.equal(flights.length, 0)
  f.reader.read = async (resource) => ({
    data: resource === "points" ? [row] : {},
  })
  await f.owner.reconnect({ kinds: ["points"] })
  assert.deepEqual(
    f.sources.get("recent-point-source")?.data.features[0]?.geometry
      .coordinates,
    [13.41, 52.51],
  )
  assert.equal(flights.length, 1)
  assert.equal(flights[0].zoom, 14)
  await new Promise(resolve => setImmediate(resolve))
  assert.deepEqual(messages, ["New location recorded"])
  await f.owner.update({ ...f.owner.config, liveEnabled: false })
  await f.owner.reconnect({ kinds: ["points"] })
  assert.equal(flights.length, 1)
  assert.equal(
    f.sources.get("recent-point-source")?.data.features.length ?? 0,
    0,
  )
  await f.owner.update({ ...f.owner.config, liveEnabled: true })
  let release,
    pointReads = 0
  f.reader.read = (resource) =>
    resource === "points" && ++pointReads !== 2
      ? new Promise((resolve) => {
          release = resolve
        })
      : Promise.resolve({ data: resource === "points" ? [] : {} })
  const stale = f.owner.reconnect({ kinds: ["points"] })
  for (let n = 0; n < 20 && !release; n++)
    await new Promise((resolve) => setImmediate(resolve))
  assert.ok(release)
  const staleRelease = release
  const rangeReady = await f.owner.update({
    ...f.owner.config,
    range: {
      ...f.owner.config.range,
      startAt: "2026-04-01T00:00",
      endAt: "2026-04-01T23:59",
    },
  })
  assert.equal(rangeReady, "ready")
  staleRelease({ data: [{ ...row, id: 38, latitude: 52.52 }] })
  await stale
  assert.equal(flights.length, 1)
  release = undefined
  const pending = f.owner.reconnect({ kinds: ["points"] })
  for (let n = 0; n < 20 && !release; n++)
    await new Promise((resolve) => setImmediate(resolve))
  assert.ok(release)
  f.owner.destroy()
  release({ data: [{ ...row, id: 39, latitude: 52.53 }] })
  await pending
  assert.equal(flights.length, 1)
  assert.equal(f.sources.has("recent-point-source"), false)
})

test("native live marker ignores notifications without a new current range row", async () => {
  const f = fixture({ liveEnabled: true })
  let flights = 0
  f.map.flyTo = () => flights++
  f.reader.read = async (resource) => ({
    data: resource === "points" ? [row] : {},
  })
  await f.owner.mount()
  await f.owner.reconnect({ kinds: ["points"] })
  assert.equal(flights, 0)
  assert.equal(
    f.sources.get("recent-point-source")?.data.features.length ?? 0,
    0,
  )
  f.owner.destroy()
})

test("native live marker retains a point arriving during the enabling baseline", async () => {
  const f = fixture({ liveEnabled: false })
  f.reader.read = async (resource) => ({
    data: resource === "points" ? [] : {},
  })
  await f.owner.mount()
  let baselineStarted
  const started = new Promise((resolve) => {
    baselineStarted = resolve
  })
  let finishBaseline
  f.reader.read = (resource) => {
    if (resource !== "points") return Promise.resolve({ data: {} })
    baselineStarted()
    return new Promise((resolve) => {
      finishBaseline = resolve
    })
  }
  const enabling = f.owner.update({ ...f.owner.config, liveEnabled: true })
  await started
  f.reader.read = async (resource) => ({
    data: resource === "points" ? [row] : {},
  })
  await f.owner.reconnect({ kinds: ["points"] })
  finishBaseline({ data: [] })
  await enabling
  assert.deepEqual(
    f.sources.get("recent-point-source")?.data.features[0]?.geometry
      .coordinates,
    [13.41, 52.51],
  )
  f.owner.destroy()
})

test("native live marker survives a panel refresh superseding its point invalidation", async () => {
  const f = fixture({ liveEnabled: true, familyEnabled: true })
  const result = (resource, points = []) => ({
    data:
      resource === "points"
        ? points
        : resource === "family_locations"
          ? { locations: [] }
          : { members: [] },
  })
  f.reader.read = async (resource) => result(resource)
  await f.owner.mount()
  let started, release
  const reading = new Promise((resolve) => {
    started = resolve
  })
  f.reader.read = (resource) => {
    if (resource === "points" && !release) {
      started()
      return new Promise((resolve) => {
        release = resolve
      })
    }
    return Promise.resolve(result(resource, [row]))
  }
  const delivery = f.owner.reconnect({ kinds: ["points"] })
  await reading
  try {
    await f.owner.update({ ...f.owner.config, panel: "family" })
    release(result("points", [row]))
    await delivery
    assert.deepEqual(
      f.sources.get("recent-point-source")?.data.features[0]?.geometry
        .coordinates,
      [13.41, 52.51],
    )
  } finally {
    release(result("points", [row]))
    await delivery
    f.owner.destroy()
  }
})
