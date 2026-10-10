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
