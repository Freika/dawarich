import assert from "node:assert/strict"
import { test } from "node:test"
import { MapHook } from "../../app-phoenix/assets/js/hooks/map.js"
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
    appendChild() {
      calls.roots++
    },
    ownerDocument: {
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
    refresh: async () => {
      calls.refreshes++
    },
    attach: options.attach,
  })
  return { runtime, calls, MockMap }
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
