import assert from "node:assert/strict"
import test from "node:test"
import { createMapRuntime } from "../../assets/js/map/runtime/create_map.js"

function runtime() {
  const styles = []
  const element = {
    dataset: {},
    querySelector: () => null,
    ownerDocument: { defaultView: null, createElement: () => ({ style: {} }) },
    appendChild() {},
  }
  const owner = createMapRuntime({
    element,
    config: { styleName: "light", range: { startAt: "a" } },
    reader: { destroy() {}, reset() {} },
    loadLibrary: async () => ({}),
    loadStyle: (config) => {
      styles.push(config.styleName)
      return new Promise(() => {})
    },
  })
  return { owner, styles }
}

const ticks = async () => {
  for (let n = 0; n < 5; n++) await Promise.resolve()
}

test("an unchanged configuration during mounting does not restart the style load", async () => {
  const { owner, styles } = runtime()
  owner.mount()
  await ticks()
  owner.update({ styleName: "light", range: { startAt: "a" } })
  await ticks()
  assert.deepEqual(styles, ["light"])
  owner.destroy()
})

test("a changed configuration during mounting restarts with the new style", async () => {
  const { owner, styles } = runtime()
  owner.mount()
  await ticks()
  owner.update({ styleName: "dark", range: { startAt: "a" } })
  await ticks()
  assert.deepEqual(styles, ["light", "dark"])
  owner.destroy()
})

test("the map attribution is compact without the MapLibre credit, as on Rails", async () => {
  const options = []
  class FakeMap {
    constructor(opts) {
      options.push(opts)
    }
    remove() {}
    addControl() {}
  }
  const element = {
    dataset: {},
    querySelector: () => null,
    ownerDocument: {
      defaultView: null,
      createElement: () => ({ style: {}, remove() {} }),
    },
    appendChild() {},
  }
  const owner = createMapRuntime({
    element,
    config: { styleName: "light", range: { startAt: "a" } },
    reader: { destroy() {}, reset() {} },
    loadLibrary: async () => ({ Map: FakeMap }),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
  })
  owner.mount()
  await ticks()
  assert.deepEqual(options[0]?.attributionControl, { compact: true })
  owner.destroy()
})

test("container resizes during the panel slide resize the map once, as Rails does after the transition", async () => {
  let observe = null
  let resizes = 0
  const pending = new Map()
  let clock = 0
  const timers = {
    setTimeout: (fn, ms) => {
      const id = Symbol()
      pending.set(id, { fn, at: clock + ms })
      return id
    },
    clearTimeout: (id) => pending.delete(id),
  }
  const advance = (ms) => {
    clock += ms
    for (const [id, { fn, at }] of [...pending])
      if (at <= clock) {
        pending.delete(id)
        fn()
      }
  }
  class FakeMap {
    remove() {}
    addControl() {}
    resize() {
      resizes++
    }
  }
  class Observer {
    constructor(callback) {
      observe = callback
    }
    observe() {}
    disconnect() {}
  }
  const element = {
    dataset: {},
    querySelector: () => null,
    ownerDocument: {
      defaultView: {
        ResizeObserver: Observer,
        addEventListener() {},
        removeEventListener() {},
      },
      createElement: () => ({ style: {}, remove() {} }),
    },
    appendChild() {},
  }
  const owner = createMapRuntime({
    element,
    config: { styleName: "light", range: { startAt: "a" } },
    reader: { destroy() {}, reset() {} },
    loadLibrary: async () => ({ Map: FakeMap }),
    loadStyle: async () => ({ version: 8, sources: {}, layers: [] }),
    timers,
  })
  owner.mount()
  await ticks()
  for (let frame = 0; frame < 5; frame++) {
    observe()
    advance(60)
  }
  assert.equal(resizes, 0)
  advance(400)
  assert.equal(resizes, 1)
  owner.destroy()
})
