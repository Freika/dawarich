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
