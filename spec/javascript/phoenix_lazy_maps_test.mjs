import assert from "node:assert/strict"
import test from "node:test"
import {
  FamilyMap,
  SharedMap,
} from "../../app-phoenix/assets/js/hooks/lazy_maps.js"

function setup(hook, name, snapshot, clear) {
  const events = new Map()
  const canvas = { hidden: false, replaceChildren() {} }
  const content = { hidden: false }
  const row = { hidden: false }
  const details = { publicPhotos: ["private"] }
  const gallery = { replaceChildren() {} }
  const status = { hidden: true, textContent: "private" }
  const el = {
    querySelector(selector) {
      if (selector.includes("canvas")) return canvas
      if (selector.includes("public-content")) return content
      return status
    },
    querySelectorAll(selector) {
      if (selector.startsWith("details")) return [details]
      if (selector.includes("img")) return []
      return [gallery]
    },
    closest: () => ({ querySelectorAll: () => [row] }),
  }
  let release
  const deferred = new Promise((resolve) => {
    release = resolve
  })
  const deliveries = []
  let mounts = 0
  const runtime = {
    mounted() {
      mounts++
      this.handleEvent(snapshot, (data) => deliveries.push(data))
      this.handleEvent(clear, () => {})
    },
    destroyed() {},
    disconnected() {},
  }
  const instance = {
    ...hook,
    el,
    loadRuntime: () => deferred,
    handleEvent(event, callback) {
      events.set(event, callback)
      return event
    },
    removeHandleEvent(event) {
      events.delete(event)
    },
    pushEvent() {},
  }
  instance.mounted()
  return {
    instance,
    events,
    content,
    row,
    canvas,
    details,
    deliveries,
    release: () => release({ [name]: runtime }),
    mounts: () => mounts,
  }
}

for (const [label, hook, name, snapshot, clear] of [
  [
    "public",
    SharedMap,
    "SharedMap",
    "public-share-snapshot",
    "public-share-clear",
  ],
  ["family", FamilyMap, "FamilyMap", "family-locations", "family-clear"],
]) {
  test(`lazy ${label} map drops a revoked snapshot before runtime initialization`, async () => {
    const c = setup(hook, name, snapshot, clear)
    assert.ok(c.instance.ready instanceof Promise)
    c.events.get(snapshot)({ private: true })
    c.events.get(clear)({})
    assert.equal(c.canvas.hidden, true)
    assert.equal(label === "public" ? c.content.hidden : c.row.hidden, true)
    assert.deepEqual(
      c.details.publicPhotos,
      label === "public" ? [] : ["private"],
    )
    c.release()
    await c.instance.ready
    assert.deepEqual(c.deliveries, [])
    c.events.get(snapshot)({ fresh: true })
    assert.deepEqual(c.deliveries, [{ fresh: true }])
    c.instance.destroyed()
    assert.equal(c.events.size, 0)
  })

  test(`lazy ${label} map cannot initialize after destruction`, async () => {
    const c = setup(hook, name, snapshot, clear)
    assert.ok(c.instance.ready instanceof Promise)
    c.events.get(snapshot)({ private: true })
    c.instance.destroyed()
    c.release()
    await c.instance.ready
    assert.equal(c.mounts(), 0)
    assert.equal(c.events.size, 0)
  })
}
