import assert from "node:assert/strict"
import test from "node:test"
import { PublicGallery } from "../../assets/js/hooks/public_gallery.js"

test("public gallery toggles deliver the day and release the listener on teardown", () => {
  const el = new EventTarget()
  el.dataset = { publicDay: "2026-05-10" }
  el.open = false
  const events = []
  const hook = {
    el,
    pushEvent: (event, params) => events.push({ event, ...params }),
  }
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

test("native public day rows release hover and focus listeners without fetching or opening photos", async (t) => {
  const { bindPublicDays } = await import(
    "../../assets/js/map/public/day_hover.js"
  )
  t.mock.method(globalThis, "fetch", () =>
    assert.fail("hover must remain local"),
  )
  const root = new EventTarget()
  const row = { dataset: { publicDay: "2026-05-10" }, closest: () => root }
  const days = []
  const stop = bindPublicDays(root, { preview: (day) => days.push(day) })
  function send(type, related = null) {
    const event = new Event(type)
    Object.defineProperty(event, "target", { value: { closest: () => row } })
    Object.defineProperty(event, "relatedTarget", { value: related })
    root.dispatchEvent(event)
  }
  send("mouseover")
  send("mouseout")
  send("focusin")
  send("focusout")
  send("mouseout", { closest: () => row })
  assert.deepEqual(days, ["2026-05-10", null, "2026-05-10", null])
  stop()
  stop()
  send("mouseover")
  assert.equal(days.length, 4)
})

test("public day decoration uses admitted colors and clears its selection without touching another map", async () => {
  const { syncPublicDays } = await import(
    "../../assets/js/map/public/day_hover.js"
  )
  const root = {},
    other = {}
  const dot = (day, owner) => ({
    dataset: { dayDot: day },
    style: { backgroundColor: "old" },
    closest: () => owner,
  })
  const row = (day) => ({
    dataset: { publicDay: day },
    classes: new Set(),
    closest: () => root,
    classList: {
      toggle(name, value) {
        value ? this.owner.classes.add(name) : this.owner.classes.delete(name)
      },
    },
  })
  const rows = [row("2026-05-10"), row("2026-05-11")]
  rows.forEach((value) => {
    value.classList.owner = value
  })
  const dots = [
    dot("2026-05-10", root),
    dot("2026-05-11", root),
    dot("2026-05-10", other),
  ]
  root.querySelectorAll = (selector) =>
    selector === "[data-day-dot]" ? dots : rows
  syncPublicDays(
    root,
    (day) => (day === "2026-05-10" ? "#6366f1" : null),
    "2026-05-10",
  )
  assert.deepEqual(
    dots.map((value) => value.style.backgroundColor),
    ["#6366f1", "", "old"],
  )
  assert.deepEqual([...rows[0].classes], ["ring-2", "ring-primary"])
  assert.equal(rows[1].classes.size, 0)
  syncPublicDays(root)
  assert.equal(dots[0].style.backgroundColor, "")
  assert.equal(rows[0].classes.size, 0)
})

test("unmapped row clicks keep disclosure defaults and mapped plain rows activate once with Space", async () => {
  const { bindPublicDays } = await import(
    "../../assets/js/map/public/day_hover.js"
  )
  const root = new EventTarget()
  let mapped = false,
    clicks = 0
  const row = {
    tagName: "DIV",
    dataset: { publicDay: "2026-05-10" },
    closest: () => root,
    click: () => clicks++,
  }
  const stop = bindPublicDays(root, { preview() {}, hasDay: () => mapped })
  function send(type, key) {
    const event = new Event(type, { cancelable: true })
    Object.defineProperty(event, "target", { value: { closest: () => row } })
    Object.defineProperty(event, "key", { value: key })
    root.dispatchEvent(event)
    return event
  }
  const refused = send("click")
  assert.equal(refused.cancelBubble, true)
  assert.equal(refused.defaultPrevented, false)
  mapped = true
  assert.equal(send("keydown", " ").defaultPrevented, true)
  assert.equal(clicks, 1)
  row.tagName = "DETAILS"
  assert.equal(send("keydown", " ").defaultPrevented, false)
  assert.equal(clicks, 1)
  stop()
})

test("public day DOM observation is scoped and late callbacks stop after teardown", async () => {
  const { bindPublicDays } = await import(
    "../../assets/js/map/public/day_hover.js"
  )
  const root = new EventTarget(),
    target = {}
  let notify,
    observed,
    stopped = 0,
    syncs = 0
  root.querySelector = () => target
  root.ownerDocument = {
    defaultView: {
      MutationObserver: class {
        constructor(callback) {
          notify = callback
        }
        observe(node) {
          observed = node
        }
        disconnect() {
          stopped++
        }
      },
    },
  }
  const stop = bindPublicDays(root, { preview() {}, sync: () => syncs++ })
  assert.equal(observed, target)
  notify()
  assert.equal(syncs, 1)
  stop()
  notify()
  assert.equal(stopped, 1)
  assert.equal(syncs, 1)
})
