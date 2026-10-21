import assert from "node:assert/strict"
import { test } from "node:test"
import { AreaPreview } from "../../app-phoenix/assets/js/hooks/area_preview.js"
import { fixture } from "./support/native_m6_host_fixture.mjs"

function hookFixture() {
  const fields = {
    latitude: { value: "52.5" },
    longitude: { value: "13.4" },
    radius: { value: "100" },
  }
  const events = [],
    listeners = new Map()
  let current
  const root = {
    querySelector: () => current,
    dispatchEvent: (event) => events.push(event.detail),
  }
  const element = {
    closest: () => root,
    querySelector(selector) {
      return fields[
        Object.keys(fields).find((name) => selector.includes(`"${name}"`))
      ]
    },
    addEventListener: (event, handler) => listeners.set(event, handler),
    removeEventListener: (event, handler) => {
      if (listeners.get(event) === handler) listeners.delete(event)
    },
  }
  current = element
  const hook = { el: element, ...AreaPreview }
  return {
    hook,
    fields,
    events,
    listeners,
    replace() {
      current = {}
    },
    remove() {
      current = null
    },
  }
}

test("native Area hook previews the current radius and clears its own close", () => {
  const f = hookFixture()
  f.hook.mounted()
  assert.deepEqual(f.events.at(-1), {
    latitude: 52.5,
    longitude: 13.4,
    radius: 100,
  })
  f.fields.radius.value = "250"
  f.listeners.get("input")()
  assert.equal(f.events.at(-1).radius, 250)
  f.fields.radius.value = "-5"
  f.hook.updated()
  assert.equal(f.events.at(-1).radius, -5)
  f.remove()
  f.hook.destroyed()
  assert.equal(f.events.at(-1), null)
  assert.equal(f.listeners.size, 0)
})
test("replaced Area hook cannot clear or republish a newer dialog preview", () => {
  const f = hookFixture()
  f.hook.mounted()
  const count = f.events.length
  f.replace()
  f.hook.updated()
  f.hook.destroyed()
  assert.equal(f.events.length, count)
  assert.equal(f.listeners.size, 0)
})
test("production Area radius preview belongs to one map root and clears on close", async () => {
  const first = fixture(),
    second = fixture()
  try {
    await first.owner.mount()
    await second.owner.mount()
    first.root.emit("native:area-preview", {
      detail: { latitude: 52.5, longitude: 13.4, radius: 250 },
    })
    assert.equal(
      first.sources.get("native-area-preview").data.features[0].geometry.type,
      "Polygon",
    )
    assert.equal(second.sources.has("native-area-preview"), false)
    first.root.emit("native:area-preview", { detail: null })
    assert.equal(first.sources.has("native-area-preview"), false)
    assert.equal(first.layers.has("native-area-preview-fill"), false)
    first.owner.destroy()
    first.root.emit("native:area-preview", {
      detail: { latitude: 52, longitude: 13, radius: 100 },
    })
    assert.equal(first.sources.has("native-area-preview"), false)
  } finally {
    first.owner.destroy()
    second.owner.destroy()
  }
})
