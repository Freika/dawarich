import assert from "node:assert/strict"
import test from "node:test"
import { ReplayPhotoStack } from "../../app-phoenix/assets/js/map/replay/photo_stack.js"
import { Element } from "./support/native_m6_host_fixture.mjs"

function popupLibrary() {
  const popups = []
  class Popup {
    constructor() {
      this.removed = false
      popups.push(this)
    }
    setLngLat() {
      return this
    }
    setHTML(html) {
      this.html = html
      return this
    }
    addTo() {
      return this
    }
    on() {
      return this
    }
    off() {
      return this
    }
    remove() {
      this.removed = true
    }
  }
  return { Popup, popups }
}

test("closing replay photo stack releases its popup thumbnails and card listeners", async () => {
  const container = new Element(),
    library = popupLibrary(),
    reads = []
  const stack = new ReplayPhotoStack({
    container,
    document: { createElement: () => new Element() },
    map: {},
    library,
    timezone: "UTC",
    reader: {
      async read(resource, params) {
        reads.push({ resource, params })
        return { data: new Blob(["synthetic"]) }
      },
    },
  })
  stack.sync(
    Array.from({ length: 7 }, (_, id) => ({
      id,
      source: "immich",
      lon: 13,
      lat: 52,
      taken_at: "2026-03-30T09:00:00Z",
    })),
  )
  await stack.ready
  assert.equal(stack.cards.size, 5)
  assert.deepEqual([...stack.cards.keys()], [2, 3, 4, 5, 6])
  assert.equal(
    reads.every((read) => read.resource === "thumbnail"),
    true,
  )
  const card = stack.cards.get(6).element
  card.emit("click", { stopPropagation() {} })
  assert.equal(library.popups.length, 1)
  stack.destroy()
  assert.equal(library.popups[0].removed, true)
  card.emit("click", { stopPropagation() {} })
  assert.equal(library.popups.length, 1)
  assert.deepEqual(container.children, [])
})
