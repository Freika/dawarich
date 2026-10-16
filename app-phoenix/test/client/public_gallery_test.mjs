import assert from "node:assert/strict"
import test from "node:test"
import { PublicGallery } from "../../assets/js/hooks/public_gallery.js"

test("public gallery toggles deliver the day and release the listener on teardown", () => {
  const el = new EventTarget()
  el.dataset = { publicDay: "2026-05-10" }
  el.open = false
  const events = []
  const hook = { el, pushEvent: (event, params) => events.push({ event, ...params }) }
  PublicGallery.mounted.call(hook)
  el.open = true
  el.dispatchEvent(new Event("toggle"))
  el.open = false
  el.dispatchEvent(new Event("toggle"))
  assert.deepEqual(events, [
    { event: "public:gallery", day: "2026-05-10", open: true },
    { event: "public:gallery", day: "2026-05-10", open: false },
  ])
  PublicGallery.destroyed.call(hook)
  el.open = true
  el.dispatchEvent(new Event("toggle"))
  assert.equal(events.length, 2)
})
