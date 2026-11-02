import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

globalThis.CustomEvent ??= class CustomEvent extends Event {
  constructor(type, options = {}) {
    super(type, options)
    this.detail = options.detail ?? null
  }
}

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
  {
    search = "",
    start = "2026-10-16T00:00",
    end = "2026-10-16T23:59",
    timelineOpen = true,
    openOverlay = false,
  } = {},
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
    inputs[selector.match(/name="([^"]+)"/)?.[1]] ||
    (openOverlay && selector.includes("dialog[open]") ? {} : null)
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
    closest: (selector) =>
      timelineOpen && selector === ".map-control-panel.open .tab-content.active"
        ? {}
        : null,
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

function pressKey(key, modifiers = {}) {
  document.dispatchEvent(
    Object.assign(new Event("keydown"), { key, ...modifiers }),
  )
}

test("arrow keys leave the day alone while the Timeline is closed", (t) => {
  const { events } = setup(t, { timelineOpen: false })
  pressKey("ArrowLeft")
  pressKey("ArrowRight")
  assert.deepEqual(events, [])
})

test("arrow keys with a modifier leave the day alone", (t) => {
  const { events } = setup(t)
  for (const modifier of ["altKey", "metaKey", "ctrlKey", "shiftKey"]) {
    pressKey("ArrowLeft", { [modifier]: true })
  }
  assert.deepEqual(events, [])
})

test("clicking a track on the rendered day loads that day so its journey can expand", (t) => {
  const { events, controller } = setup(t)
  document.dispatchEvent(
    new CustomEvent("timeline:open-track", {
      detail: { trackId: 7, date: "2026-10-16" },
    }),
  )
  assert.deepEqual(
    events.map((event) => event.date),
    ["2026-10-16"],
  )
  assert.equal(controller.pendingTrackId, 7)
})

test("timeline arrows follow a range applied outside the Timeline", (t) => {
  const { controller, inputs, events } = setup(t)
  controller.navigateDay({ currentTarget: { dataset: { direction: "next" } } })
  inputs.start_at.value = "2026-10-20T00:00"
  inputs.end_at.value = "2026-10-20T23:59"
  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: {
        startAt: "2026-10-19T22:00:00.000Z",
        endAt: "2026-10-20T21:59:59.000Z",
      },
    }),
  )
  controller.navigateDay({ currentTarget: { dataset: { direction: "prev" } } })
  assert.deepEqual(
    events.filter((event) => event.date).map((event) => event.date),
    ["2026-10-17", "2026-10-19"],
  )
})

test("arrow keys pan a focused map instead of changing the day", (t) => {
  const { events } = setup(t)
  pressKeyOn(
    {
      closest: (selector) =>
        selector.includes(".maplibregl-canvas-container") ? {} : null,
    },
    "ArrowLeft",
  )
  assert.deepEqual(events, [])
})

test("arrow keys typed into editable text leave the day alone", (t) => {
  const { events } = setup(t)
  pressKeyOn({ isContentEditable: true, closest: () => null }, "ArrowRight")
  assert.deepEqual(events, [])
})

test("arrow keys leave the day alone while a modal or studio is open", (t) => {
  const { events } = setup(t, { openOverlay: true })
  pressKey("ArrowLeft")
  assert.deepEqual(events, [])
})

test("a range applied outside the Timeline clears the highlighted day", (t) => {
  const { controller } = setup(t)
  const removed = []
  const cell = { classList: { remove: (name) => removed.push(name) } }
  controller.element.querySelectorAll = (selector) =>
    selector === ".cal-cell--selected" ? [cell] : []
  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: { startAt: "2026-10-20T00:00", endAt: "2026-10-20T23:59" },
    }),
  )
  assert.deepEqual(removed, ["cal-cell--selected"])
  assert.equal(controller.selectedDate, null)
})

test("the Timeline's own day change keeps its highlighted day", (t) => {
  const { controller } = setup(t)
  controller.navigateDay({ currentTarget: { dataset: { direction: "next" } } })
  const removed = []
  controller.element.querySelectorAll = (selector) =>
    selector === ".cal-cell--selected"
      ? [{ classList: { remove: (name) => removed.push(name) } }]
      : []
  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: { date: "2026-10-18" },
    }),
  )
  assert.deepEqual(removed, [])
  assert.equal(controller.selectedDate, "2026-10-17")
})

test("arrow keys still change the day with a Timeline button focused", (t) => {
  const { events } = setup(t)
  pressKeyOn({ matches: () => false, closest: () => null }, "ArrowRight")
  assert.deepEqual(
    events.map((event) => event.date),
    ["2026-10-17"],
  )
})

function pressKeyOn(target, key) {
  const event = new Event("keydown")
  Object.defineProperties(event, {
    key: { value: key },
    target: { value: target },
  })
  document.dispatchEvent(event)
}
