import assert from "node:assert/strict"
import test from "node:test"

const payload = (generation, revision) => ({
  kind: "ColumnChart",
  generation,
  revision,
  data: [["März", 10]],
  options: { suffix: " km" },
})

function library() {
  const calls = []
  class Chart {
    constructor(element, data, options) {
      calls.push(["create", element, data, options])
    }
    updateData(data, options) {
      calls.push(["update", data, options])
    }
    destroy() {
      calls.push(["destroy"])
    }
  }
  return { lib: { ColumnChart: Chart }, calls }
}

test("chart latest revision wins and destroys once", async () => {
  const { createAdapter } = await import(
    "../../app-phoenix/assets/js/charts/adapter.js"
  )
  const { lib, calls } = library()
  const adapter = createAdapter("plot", () => Promise.resolve(lib))
  await adapter.update(payload(2, "ready-2"))
  await adapter.update(payload(1, "stale"))
  await adapter.update(payload(2, "ready-3"))
  adapter.destroy()
  adapter.destroy()
  assert.deepEqual(
    calls.map((c) => c[0]),
    ["create", "update", "destroy"],
  )
  assert.deepEqual(calls[0][2], [["März", 10]])
  assert.equal(calls[0][3].suffix, " km")
})

test("lazy library completion after destroy creates no chart", async () => {
  const { createAdapter } = await import(
    "../../app-phoenix/assets/js/charts/adapter.js"
  )
  const { lib, calls } = library()
  let finish
  const adapter = createAdapter(
    "plot",
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  const pending = adapter.update(payload(1, "first"))
  adapter.destroy()
  finish(lib)
  await pending
  assert.equal(calls.length, 0)
})

test("a delayed library applies only the newest bounded chart projection", async () => {
  const { createAdapter } = await import(
    "../../app-phoenix/assets/js/charts/adapter.js"
  )
  const { lib, calls } = library()
  let finish
  const adapter = createAdapter(
    "plot",
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  const old = adapter.update(payload(1, "old"))
  const current = adapter.update({
    ...payload(2, "new"),
    data: [["April", 20]],
  })
  finish(lib)
  await Promise.all([old, current])
  assert.equal(calls.length, 1)
  assert.deepEqual(calls[0][2], [["April", 20]])
  await assert.rejects(
    adapter.update({
      ...payload(3, "oversize"),
      data: Array(367).fill(["day", 1]),
    }),
    /invalid chart/,
  )
  adapter.destroy()
})

test("public chart initialization is independent and repeated cleanup is idempotent", async () => {
  const { initializeCharts } = await import(
    "../../app-phoenix/assets/js/public_charts.js"
  )
  const element = {
    dataset: { chart: JSON.stringify(payload(1, "public")) },
    querySelector: () => "plot",
  }
  const root = { querySelectorAll: () => [element] }
  let created = 0
  let destroyed = 0
  const factory = () => {
    created++
    return {
      update() {
        return Promise.resolve()
      },
      destroy() {
        destroyed++
      },
    }
  }
  const cleanup = initializeCharts(root, factory)
  const again = initializeCharts(root, factory)
  assert.equal(created, 1)
  cleanup()
  again()
  assert.equal(destroyed, 1)
})

test("a failed lazy chart load can retry the same revision", async () => {
  const { createAdapter } = await import(
    "../../app-phoenix/assets/js/charts/adapter.js"
  )
  const { lib, calls } = library()
  let attempts = 0
  const adapter = createAdapter("plot", () =>
    ++attempts === 1
      ? Promise.reject(new Error("offline"))
      : Promise.resolve(lib),
  )
  await assert.rejects(adapter.update(payload(1, "same")), /offline/)
  await adapter.update(payload(1, "same"))
  assert.equal(attempts, 2)
  assert.equal(calls.length, 1)
  adapter.destroy()
})

test("public charts survive persisted history hide and show and clean up on final leave", async () => {
  const { initializePublicCharts } = await import(
    "../../app-phoenix/assets/js/public_charts.js"
  )
  const target = new EventTarget()
  const element = {
    dataset: { chart: JSON.stringify(payload(1, "history")) },
    querySelector: () => "plot",
  }
  const root = { querySelectorAll: () => [element] }
  let created = 0
  let destroyed = 0
  const factory = () => {
    created++
    return { update: () => Promise.resolve(), destroy: () => destroyed++ }
  }
  const stop = initializePublicCharts(root, target, factory)
  const lifecycle = (type, persisted) =>
    target.dispatchEvent(Object.assign(new Event(type), { persisted }))
  for (let i = 0; i < 2; i++) {
    lifecycle("pagehide", true)
    lifecycle("pageshow", true)
    assert.equal(created, 1)
    assert.equal(destroyed, 0)
  }
  lifecycle("pagehide", false)
  assert.equal(destroyed, 1)
  stop()
  assert.equal(destroyed, 1)
})

test("public monthly previews cannot mount after their document leaves", async () => {
  const { initializePublicPreviews } = await import(
    "../../app-phoenix/assets/js/public_charts.js"
  )
  let resolve,
    mounted = 0,
    destroyed = 0
  const loading = new Promise((done) => {
    resolve = done
  })
  const events = new Map()
  const target = {
    addEventListener: (name, fn) => events.set(name, fn),
    removeEventListener: (name) => events.delete(name),
  }
  const cleanup = initializePublicPreviews(
    { querySelectorAll: () => [{}] },
    target,
    () => loading,
  )
  events.get("pagehide")({ persisted: false })
  resolve({
    mountPreview: () => ({
      mount: () => mounted++,
      destroy: () => destroyed++,
    }),
  })
  await loading
  await Promise.resolve()
  assert.equal(mounted, 0)
  cleanup()
  assert.equal(destroyed, 0)
})

test("public monthly initializer shares one preview owner across repeated initialization", async () => {
  const { initializePublicPreviews } = await import(
    "../../app-phoenix/assets/js/public_charts.js"
  )
  const element = {}
  let mounted = 0,
    removed = 0
  const root = { querySelectorAll: () => [element] }
  const target = { addEventListener() {}, removeEventListener() {} }
  const load = async () => ({
    mountPreview: () => ({ mount: () => mounted++, destroy: () => removed++ }),
  })
  const first = initializePublicPreviews(root, target, load)
  const second = initializePublicPreviews(root, target, load)
  await Promise.resolve()
  await Promise.resolve()
  assert.equal(mounted, 1)
  first()
  second()
  assert.equal(removed, 1)
})

test("public report charts mount directly into their Rails plot container", async () => {
  const { initializeCharts } = await import("../../app-phoenix/assets/js/public_charts.js")
  const plot = {
    dataset: { chart: JSON.stringify(payload(1, "rails-plot")) },
    matches: (selector) => selector === "[data-chart-plot]",
    querySelector: () => null,
  }
  let target
  const stop = initializeCharts({ querySelectorAll: () => [plot] }, (element) => {
    target = element
    return { update: () => Promise.resolve(), destroy() {} }
  })
  assert.equal(target, plot)
  stop()
})

test("public month loading clears on map settlement and observers stop on document leave", async () => {
  const { trackPreviewLoading } = await import("../../app-phoenix/assets/js/public_charts.js")
  const loading = { hidden: false }
  const plot = {
    dataset: { mapState: "loading" },
    closest: () => ({ querySelector: () => loading }),
  }
  let changed
  let disconnected = 0
  const stop = trackPreviewLoading(plot, (callback) => {
    changed = callback
    return { observe() {}, disconnect() { disconnected += 1 } }
  })
  assert.equal(loading.hidden, false)
  for (const state of ["ready", "failed"]) {
    plot.dataset.mapState = state
    changed()
    assert.equal(loading.hidden, true)
  }
  plot.dataset.mapState = "loading"
  changed()
  assert.equal(loading.hidden, false)
  stop()
  stop()
  assert.equal(disconnected, 1)
  plot.dataset.mapState = "ready"
  changed()
  assert.equal(loading.hidden, false)
})
