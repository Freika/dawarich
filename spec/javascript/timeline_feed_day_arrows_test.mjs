import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/timeline_feed_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const { default: TimelineFeedController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

function setup(
  t,
  { search = "", start = "2026-10-16T00:00", end = "2026-10-16T23:59" } = {},
) {
  const originals = Object.fromEntries(
    ["document", "window", "requestAnimationFrame"].map((key) => [
      key,
      globalThis[key],
    ]),
  )
  const document = new EventTarget()
  const inputs = { start_at: { value: start }, end_at: { value: end } }
  document.querySelector = (selector) =>
    inputs[selector.match(/name="([^"]+)"/)?.[1]] || null
  document.getElementById = () => null
  let location = new URL(`https://example.test/map/v2${search}`)
  globalThis.document = document
  globalThis.window = {
    get location() {
      return location
    },
    history: {
      pushState(_state, _title, url) {
        location = new URL(url, location)
      },
    },
  }
  globalThis.requestAnimationFrame = (callback) => callback()
  const controller = new TimelineFeedController()
  const attributes = { src: "/map/timeline_feeds" }
  controller.element = {
    isConnected: true,
    querySelector: () => null,
    querySelectorAll: () => [],
  }
  controller.hasVisitListFrameTarget = true
  controller.visitListFrameTarget = Object.assign(new EventTarget(), {
    getAttribute: (name) => attributes[name],
    setAttribute: (name, value) => {
      attributes[name] = value
    },
  })
  const events = []
  document.addEventListener("timeline-feed:date-navigated", (event) =>
    events.push(event.detail),
  )
  controller.connect()
  t.after(() => {
    controller.disconnect()
    Object.assign(globalThis, originals)
  })
  return { controller, inputs, events, attributes }
}

for (const [direction, expected] of [
  ["prev", "2026-10-15"],
  ["next", "2026-10-17"],
]) {
  test(`timeline ${direction} starts from the rendered day without URL parameters or calendar selection`, (t) => {
    const { controller, inputs, events, attributes } = setup(t)
    controller.navigateDay({ currentTarget: { dataset: { direction } } })
    assert.deepEqual(
      events.map((event) => event.date),
      [expected],
    )
    assert.equal(inputs.start_at.value, `${expected}T00:00`)
    assert.equal(inputs.end_at.value, `${expected}T23:59`)
    assert.equal(window.location.searchParams.get("date"), expected)
    assert.equal(window.location.searchParams.get("panel"), "timeline")
    assert.equal(
      new URL(attributes.src, window.location).searchParams.get("end_at"),
      `${expected}T23:59:59`,
    )
  })
  test(`keyboard ${direction} starts from the rendered day without calendar selection`, (t) => {
    const { events } = setup(t)
    document.dispatchEvent(
      Object.assign(new Event("keydown"), {
        key: direction === "prev" ? "ArrowLeft" : "ArrowRight",
      }),
    )
    assert.deepEqual(
      events.map((event) => event.date),
      [expected],
    )
  })
  test(`timeline ${direction} starts from the last rendered day of a three-day URL range`, (t) => {
    const { controller, events } = setup(t, {
      search: "?start_at=2026-10-14T00:00&end_at=2026-10-16T23:59",
      start: "2026-10-14T00:00",
    })
    controller.navigateDay({ currentTarget: { dataset: { direction } } })
    assert.deepEqual(
      events.map((event) => event.date),
      [expected],
    )
  })
}

test("timeline hydration uses the rendered last day even without URL range parameters", (t) => {
  const { controller, inputs } = setup(t, {
    search: "?panel=timeline",
    start: "2026-10-14T00:00",
  })
  assert.equal(controller.selectedDate, "2026-10-16")
  assert.equal(inputs.start_at.value, "2026-10-14T00:00")
})
