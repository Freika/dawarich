import assert from "node:assert/strict"
import { test } from "node:test"
import { MapHook } from "../../app-phoenix/assets/js/map/hooks/map.js"
import { createMapRuntime } from "../../app-phoenix/assets/js/map/runtime/create_map.js"

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}
function fixture(options = {}) {
  const calls = { maps: 0, removed: 0, roots: 0, refreshes: 0, readers: 0 }
  const element = {
    dataset: {},
    appendChild() {
      calls.roots++
    },
    ownerDocument: {
      defaultView: options.window,
      createElement() {
        return {
          style: {},
          remove() {
            calls.roots--
          },
        }
      },
    },
  }
  class MockMap {
    constructor(config) {
      calls.maps++
      this.config = config
      if (options.fail === "constructor") throw new Error("constructor")
    }
    remove() {
      calls.removed++
    }
  }
  const reader = {
    reset() {},
    destroy() {
      calls.readers++
    },
  }
  const runtime = createMapRuntime({
    element,
    reader,
    config: options.config ?? {},
    loadLibrary: options.loadLibrary ?? (async () => ({ Map: MockMap })),
    loadStyle: options.loadStyle ?? (async () => ({})),
    refresh:
      options.refresh ??
      (async () => {
        calls.refreshes++
      }),
    events: options.events,
    attach: options.attach,
    timers: options.timers,
  })
  return { runtime, calls, MockMap, element }
}

test("destroy while chunk or style resolves creates no orphan map", async () => {
  for (const stage of ["chunk", "style"]) {
    const pending = deferred()
    const options =
      stage === "chunk"
        ? { loadLibrary: () => pending.promise }
        : { loadStyle: () => pending.promise }
    const { runtime, calls, MockMap } = fixture(options)
    const mounting = runtime.mount()
    await Promise.resolve()
    runtime.destroy()
    pending.resolve(stage === "chunk" ? { Map: MockMap } : {})
    assert.equal(await mounting, "cancelled")
    assert.equal(calls.maps, 0)
    assert.equal(calls.roots, 0)
  }
})

test("reconnect preserves exactly one map", async () => {
  const { runtime, calls } = fixture()
  assert.equal(await runtime.mount(), "ready")
  const map = runtime.map
  for (let i = 0; i < 10; i++) await runtime.reconnect()
  assert.equal(runtime.map, map)
  assert.equal(calls.maps, 1)
  assert.equal(calls.refreshes, 11)
  runtime.destroy()
  runtime.destroy()
  assert.equal(calls.removed, 1)
  assert.equal(calls.readers, 1)
  assert.equal(calls.roots, 0)
})

test("two map owners cannot dispose each other", async () => {
  const one = fixture()
  const two = fixture()
  await one.runtime.mount()
  await two.runtime.mount()
  one.runtime.destroy()
  assert.equal(two.calls.removed, 0)
  assert.equal(two.calls.readers, 0)
  assert.equal(two.calls.roots, 1)
  two.runtime.destroy()
  assert.equal(two.calls.removed, 1)
})

test("map constructor or attachment failure drains acquired resources", async () => {
  for (const fail of ["constructor", "attachment"]) {
    const { runtime, calls } = fixture({
      fail,
      attach:
        fail === "attachment"
          ? () => {
              throw new Error("attachment")
            }
          : undefined,
    })
    assert.equal(await runtime.mount(), "failed")
    assert.equal(calls.roots, 0)
    assert.equal(calls.removed, fail === "attachment" ? 1 : 0)
    assert.equal(calls.readers, 1)
  }
})

test("late attachment cleanup runs after host destruction", async () => {
  const attached = deferred()
  let disposed = 0
  const { runtime, calls } = fixture({ attach: async () => attached.promise })
  const mount = runtime.mount()
  for (let i = 0; i < 6; i++) await Promise.resolve()
  assert.equal(calls.maps, 1)
  runtime.destroy()
  attached.resolve(() => disposed++)
  assert.equal(await mount, "cancelled")
  assert.equal(disposed, 1)
  assert.equal(calls.removed, 1)
})

test("destroyed lazy hooks cannot mount a late runtime", async () => {
  const pending = deferred()
  let mounted = 0
  let disposed = 0
  const hook = {
    ...MapHook,
    el: {},
    pushEvent() {},
    loader: () => pending.promise,
    handleEvent: () => 1,
    removeHandleEvent() {},
  }
  const loading = hook.mounted()
  hook.destroyed()
  pending.resolve({
    mountHost() {
      mounted++
      return {
        mount() {},
        destroy() {
          disposed++
        },
      }
    },
  })
  await loading
  assert.equal(mounted, 0)
  assert.equal(disposed, 0)
})

test("config changes invalidate old style initialization and refresh receipts", async () => {
  const oldStyle = deferred()
  const styles = []
  const { runtime, calls } = fixture({
    config: { revision: 1 },
    loadStyle: async (config) => {
      styles.push(config.revision)
      return config.revision === 1 ? oldStyle.promise : {}
    },
  })
  const mounting = runtime.mount()
  for (let i = 0; i < 6; i++) await Promise.resolve()
  const updating = runtime.update({ revision: 2 })
  for (let i = 0; i < 6; i++) await Promise.resolve()
  try {
    assert.deepEqual(styles, [1, 2])
  } finally {
    oldStyle.resolve({})
    await mounting
    await updating
    runtime.destroy()
  }
  assert.equal(calls.maps, 1)
})

test("initialization deadline drains a map waiting for attachment", async () => {
  let expire
  const timers = {
    setTimeout(fn) {
      expire = fn
      return 1
    },
    clearTimeout() {},
  }
  const attached = deferred()
  const { runtime, calls } = fixture({ timers, attach: () => attached.promise })
  const mounting = runtime.mount()
  for (let i = 0; i < 12; i++) await Promise.resolve()
  try {
    assert.equal(calls.maps, 1)
    expire()
    assert.equal(await mounting, "cancelled")
    assert.equal(calls.removed, 1)
    assert.equal(calls.roots, 0)
    assert.equal(calls.readers, 1)
  } finally {
    runtime.destroy()
    attached.resolve()
  }
})

test("production runtime publishes a current read-only root snapshot and removes it on destroy", async () => {
  const { runtime, element } = fixture({
    config: {
      revision: 1,
      range: { timezone: "UTC" },
      api_key: "synthetic-private",
    },
  })
  assert.equal(element.dawarichMapSnapshot, undefined)
  assert.equal(await runtime.mount(), "ready")
  assert.equal(element.dawarichMapSnapshot().revision, 1)
  assert.equal(
    JSON.stringify(element.dawarichMapSnapshot()).includes("synthetic-private"),
    false,
  )
  await runtime.update({ revision: 2 })
  assert.equal(element.dawarichMapSnapshot().revision, 2)
  const stale = element.dawarichMapSnapshot
  runtime.destroy()
  assert.equal(element.dawarichMapSnapshot, undefined)
  assert.equal(stale(), null)
})

test("map hook retains only latest scalar track selection across lazy mount and ignores after destroy", async () => {
  const pending = deferred()
  const handlers = new Map(),
    selections = []
  const attached = deferred()
  const entered = deferred()
  const owner = {
    config: {},
    mount: async () => {
      entered.resolve()
      return attached.promise
    },
    destroy() {},
    timeline: { select: async (receipt) => selections.push(receipt) },
  }
  const hook = {
    ...MapHook,
    el: {},
    pushEvent() {},
    loader: () => pending.promise,
    handleEvent(name, callback) {
      handlers.set(name, callback)
      return name
    },
    removeHandleEvent() {},
  }
  const mounting = hook.mounted()
  handlers.get("track:selection")({
    id: 7,
    points: false,
    geometry: "forbidden",
  })
  handlers.get("track:selection")({ id: 8, points: true, rows: "forbidden" })
  pending.resolve({ mountHost: () => owner })
  await entered.promise
  handlers.get("track:selection")({ id: 10, points: false })
  assert.equal(selections.length, 0)
  attached.resolve("ready")
  await mounting
  assert.deepEqual(selections, [{ id: 10, points: false }])
  await handlers.get("track:selection")({ id: null, points: false })
  assert.deepEqual(selections.at(-1), { id: null, points: false })
  hook.destroyed()
  await handlers.get("track:selection")({ id: 9, points: true })
  assert.equal(selections.length, 2)
})

test("map hook retains only latest scalar visit selection across lazy mount and ignores after destroy", async () => {
  const pending = deferred()
  const handlers = new Map(),
    selections = []
  const attached = deferred()
  const entered = deferred()
  const owner = {
    config: {},
    mount: async () => {
      entered.resolve()
      return attached.promise
    },
    destroy() {},
    visits: { select: async (receipt) => selections.push(receipt) },
  }
  const hook = {
    ...MapHook,
    el: {},
    pushEvent() {},
    loader: () => pending.promise,
    handleEvent(name, callback) {
      handlers.set(name, callback)
      return name
    },
    removeHandleEvent() {},
  }
  const mounting = hook.mounted()
  handlers.get("visit:selection")({
    id: 7,
    geometry: "forbidden",
  })
  handlers.get("visit:selection")({ id: 8, rows: "forbidden" })
  pending.resolve({ mountHost: () => owner })
  await entered.promise
  handlers.get("visit:selection")({ id: 10 })
  assert.equal(selections.length, 0)
  attached.resolve("ready")
  await mounting
  assert.deepEqual(selections, [{ id: 10 }])
  await handlers.get("visit:selection")({ id: null })
  assert.deepEqual(selections.at(-1), { id: null })
  hook.destroyed()
  assert.deepEqual(hook.mapHandlers, [])
  await handlers.get("visit:selection")({ id: 9 })
  assert.equal(selections.length, 2)
})

test("current ordinary map refresh deadline ends loading emits failure and rejects late geometry", async () => {
  const jobs = new Map(),
    receipts = [],
    pending = deferred()
  let next = 0,
    applied = 0,
    stall = false
  const timers = {
    setTimeout(fn) {
      jobs.set(++next, fn)
      return next
    },
    clearTimeout(id) {
      jobs.delete(id)
    },
  }
  const f = fixture({
    timers,
    events: { error: (receipt) => receipts.push(receipt) },
    refresh: async ({ operation }) => {
      if (stall) await pending.promise
      operation.check()
      applied++
    },
  })
  try {
    await f.runtime.mount()
    stall = true
    const refreshing = f.runtime.reconnect()
    await Promise.resolve()
    assert.equal(f.element.dataset.mapState, "loading")
    const expire = [...jobs.values()].at(-1)
    expire()
    assert.equal(await refreshing, "failed")
    assert.equal(f.element.dataset.mapState, "failed")
    assert.deepEqual(receipts, [{ code: "map_refresh_failed" }])
    pending.resolve()
    await new Promise((resolve) => setImmediate(resolve))
    assert.equal(applied, 1)
    stall = false
    assert.equal(await f.runtime.reconnect(), "ready")
    assert.equal(f.element.dataset.mapState, "ready")
    assert.equal(applied, 2)
    assert.equal(f.calls.maps, 1)
  } finally {
    pending.resolve()
    f.runtime.destroy()
  }
  assert.equal(jobs.size, 0)
})

test("container resize updates the viewport and destruction disconnects the observer", async () => {
  let notify,
    observed,
    disconnected = 0,
    resized = 0
  class ResizeObserver {
    constructor(callback) {
      notify = callback
    }
    observe(target) {
      observed = target
    }
    disconnect() {
      disconnected++
    }
  }
  const f = fixture({ window: { ResizeObserver } })
  await f.runtime.mount()
  f.runtime.map.resize = () => resized++
  assert.equal(observed, f.element)
  notify()
  assert.equal(resized, 1)
  f.runtime.destroy()
  assert.equal(disconnected, 1)
  notify()
  assert.equal(resized, 1)
})

test("native runtime exposes the latest published state through refresh and disposal", async () => {
  const pending = deferred()
  let wait = false
  const { runtime } = fixture({
    refresh: () => (wait ? pending.promise : Promise.resolve()),
  })
  assert.equal(await runtime.mount(), "ready")
  assert.equal(runtime.presentationState, "ready")
  wait = true
  const refreshing = runtime.reconnect()
  assert.equal(runtime.presentationState, "loading")
  pending.resolve()
  assert.equal(await refreshing, "ready")
  assert.equal(runtime.presentationState, "ready")
  runtime.destroy()
  assert.equal(runtime.presentationState, "cancelled")
})

test("native document retirement releases WebGL owners without retiring cached pages", async () => {
  const window = new EventTarget()
  const { runtime, calls } = fixture({ window })
  assert.equal(await runtime.mount(), "ready")
  const cached = new Event("pagehide")
  Object.defineProperty(cached, "persisted", { value: true })
  window.dispatchEvent(cached)
  assert.equal(calls.removed, 0)
  window.dispatchEvent(new Event("pagehide"))
  assert.equal(calls.removed, 1)
  assert.equal(calls.readers, 1)
  assert.equal(calls.roots, 0)
  runtime.destroy()
  window.dispatchEvent(new Event("pagehide"))
  assert.equal(calls.removed, 1)
})
