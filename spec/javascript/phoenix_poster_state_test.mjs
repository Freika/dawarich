import assert from "node:assert/strict"
import { test } from "node:test"
import { PosterStudio } from "../../app-phoenix/assets/js/poster/hook.js"
import { createStudioSource } from "../../app-phoenix/assets/js/map/data/studio_source.js"
import { createPosterSource } from "../../app-phoenix/assets/js/poster/source.js"
import {
  initialPosterState,
  withLoadedData,
} from "../../app-phoenix/assets/js/poster/state.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((res, rej) => {
    resolve = res
    reject = rej
  })
  return { promise, resolve, reject }
}

const route = {
  type: "Feature",
  properties: {},
  geometry: {
    type: "LineString",
    coordinates: [
      [13.4, 52.5],
      [13.5, 52.6],
    ],
  },
}
const arc = {
  type: "Feature",
  properties: { flight: true },
  geometry: {
    type: "LineString",
    coordinates: [
      [13.5, 52.6],
      [2.35, 48.85],
    ],
  },
}
const points = [
  { longitude: 13.4, latitude: 52.5, timestamp: 1 },
  { longitude: "13.5", latitude: "52.6", timestamp: 2 },
]

const mapState = (revision, startAt = "2026-10-01T00:00:00Z") => ({
  revision,
  title: "Map page",
  range: {
    startAt,
    endAt: "2026-10-02T00:00:00Z",
    importId: null,
    timezone: "Europe/Berlin",
  },
})

const throwingGlobal = () =>
  new Proxy(
    {},
    {
      get(_, key) {
        throw new Error(`global lookup ${String(key)}`)
      },
    },
  )

test("poster source never performs a controller registry lookup", async (t) => {
  const saved = { document: globalThis.document, window: globalThis.window }
  t.after(() => Object.assign(globalThis, saved))
  globalThis.document = throwingGlobal()
  globalThis.window = throwingGlobal()
  const studio = createStudioSource({
    getState: () => mapState(1),
    readSnapshot: async () => ({
      points,
      geojson: { type: "FeatureCollection", features: [route] },
    }),
  })
  const poster = createPosterSource(studio)
  const data = await poster.load()
  assert.equal(data.revision, 1)
  assert.equal(data.geojson.features.length, 1)
  assert.equal(data.timeZone, "Europe/Berlin")
  poster.destroy()
})

test("range change waits for current map revision", async () => {
  let current = mapState(1)
  const acknowledgement = deferred()
  const writes = []
  const studio = createStudioSource({
    getState: () => current,
    readSnapshot: async (state) => ({
      points,
      geojson: { type: "FeatureCollection", features: [route] },
      seenRange: state.range.startAt,
    }),
    applyDates: (range) => {
      writes.push(range)
      return acknowledgement.promise
    },
  })
  const poster = createPosterSource(studio)
  const range = { ...mapState(2, "2026-09-01T00:00:00Z").range }
  let settled = false
  const pending = poster.applyDates(range).then((data) => {
    settled = true
    return data
  })
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(settled, false)
  assert.deepEqual(writes, [range])
  current = mapState(2, "2026-09-01T00:00:00Z")
  acknowledgement.resolve({ revision: 2 })
  const data = await pending
  assert.equal(data.revision, 2)
  assert.equal(data.range.startAt, "2026-09-01T00:00:00Z")
  assert.equal(data.seenRange, "2026-09-01T00:00:00Z")

  const stale = deferred()
  const lagging = createPosterSource(
    createStudioSource({
      getState: () => mapState(3),
      readSnapshot: async () => ({ points, geojson: { features: [route] } }),
      applyDates: () => stale.promise,
    }),
  )
  const refused = lagging.applyDates(range)
  stale.resolve({ revision: 4 })
  await assert.rejects(refused, { name: "AbortError" })
})

test("trip provider remains fixed and keeps flight arcs", async () => {
  let writes = 0
  const studio = createStudioSource({
    getState: () => ({ ...mapState(7), title: "Lisbon trip" }),
    readSnapshot: async () => ({
      points,
      flights: { type: "FeatureCollection", features: [arc] },
      geojson: { type: "FeatureCollection", features: [route, arc] },
    }),
    applyDates: () => {
      writes++
    },
    fixedRange: true,
  })
  const poster = createPosterSource(studio)
  assert.equal(poster.fixed, true)
  assert.equal(poster.trackSource, "routes")
  await assert.rejects(poster.applyDates(mapState(8).range), /fixed/)
  assert.equal(writes, 0)
  const data = await poster.load()
  assert.deepEqual(data.geojson.features, [route, arc])
  assert.deepEqual(data.guardCoords, [
    [13.4, 52.5],
    [13.5, 52.6],
  ])
  assert.equal(data.flightsOmitted, true)
  assert.equal(data.defaultTitle, "Lisbon trip")
  assert.equal(poster.fallbackBounds(), null)
})

test("map source keeps an empty default title, the tracks source and live fallback bounds", async () => {
  const bounds = [
    [1, 2],
    [3, 4],
  ]
  const poster = createPosterSource(
    createStudioSource({
      getState: () => mapState(1),
      readSnapshot: async () => ({ points: [], geojson: { features: [] } }),
    }),
    { fallbackBounds: () => bounds },
  )
  const data = await poster.load()
  assert.equal(poster.fixed, false)
  assert.equal(poster.trackSource, "tracks")
  assert.equal(data.defaultTitle, "")
  assert.equal(data.flightsOmitted, false)
  assert.deepEqual(data.guardCoords, [])
  assert.equal(poster.fallbackBounds(), bounds)
})

test("destroy invalidates pending source loads", async () => {
  const pending = deferred()
  let seenSignal
  const poster = createPosterSource(
    createStudioSource({
      getState: () => mapState(1),
      readSnapshot: (_, { signal }) => {
        seenSignal = signal
        return pending.promise
      },
    }),
  )
  const load = poster.load()
  poster.destroy()
  pending.resolve({ points, geojson: { features: [route] } })
  await assert.rejects(load, { name: "AbortError" })
  assert.equal(seenSignal.aborted, true)
  await assert.rejects(poster.load(), { name: "AbortError" })
})

test("range reload refreshes only an automatic subtitle and fills a blank title", () => {
  const first = withLoadedData(
    initialPosterState(),
    { defaultTitle: "Lisbon trip" },
    "1 Oct 2026 – 2 Oct 2026",
  )
  assert.equal(first.title, "Lisbon trip")
  assert.equal(first.subtitle, "1 Oct 2026 – 2 Oct 2026")
  const auto = withLoadedData(
    first,
    { defaultTitle: "" },
    "1 Sept 2026 – 2 Sept 2026",
  )
  assert.equal(auto.subtitle, "1 Sept 2026 – 2 Sept 2026")
  assert.equal(auto.title, "Lisbon trip")
  const edited = withLoadedData(
    { ...auto, subtitle: "Holiday" },
    { defaultTitle: "" },
    "3 Sept 2026 – 4 Sept 2026",
  )
  assert.equal(edited.subtitle, "Holiday")
  assert.deepEqual(
    [...initialPosterState().hidden],
    ["buildings", "rail", "boundaries"],
  )
})

function hookElement() {
  const target = new EventTarget()
  target.dataset = {}
  return target
}

function mountHook(overrides = {}) {
  const hook = {
    ...PosterStudio,
    el: hookElement(),
    pushEvent: () => {},
    ...overrides,
  }
  hook.mounted()
  return hook
}

test("the studio opens only through a source injected on its own root", async () => {
  const mounts = []
  const runtime = {
    mountPosterStudio: (options) => {
      mounts.push(options)
      return { open: async () => {}, destroy: () => mounts.push("destroyed") }
    },
  }
  let loads = 0
  const hook = mountHook({
    loader: async () => {
      loads++
      return runtime
    },
  })
  hook.el.dispatchEvent(
    new CustomEvent("dawarich:poster-studio-open", { detail: {} }),
  )
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(loads, 0)
  const studio = { snapshot: async () => ({}) }
  const fallbackBounds = () => null
  const openVideo = () => {}
  hook.el.dispatchEvent(
    new CustomEvent("dawarich:poster-studio-open", {
      detail: { source: studio, fallbackBounds, openVideo },
    }),
  )
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(mounts.length, 1)
  assert.equal(mounts[0].source, studio)
  assert.equal(mounts[0].fallbackBounds, fallbackBounds)
  assert.equal(mounts[0].openVideo, openVideo)
  assert.equal(mounts[0].root, hook.el)
  hook.destroyed()
  assert.deepEqual(mounts.slice(1), ["destroyed"])
})

test("destroy before the studio chunk resolves creates no studio", async () => {
  const chunk = deferred()
  let mounted = 0
  const hook = mountHook({ loader: () => chunk.promise })
  hook.el.dispatchEvent(
    new CustomEvent("dawarich:poster-studio-open", {
      detail: { source: { snapshot: async () => ({}) } },
    }),
  )
  hook.destroyed()
  chunk.resolve({
    mountPosterStudio: () => {
      mounted++
      return { open: async () => {}, destroy: () => {} }
    },
  })
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(mounted, 0)
})
