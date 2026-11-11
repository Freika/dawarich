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
  document.querySelectorAll = () => []
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
    querySelector: () => null,
    querySelectorAll: () => [],
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

test("a period of several days opens whole, with no day selected", (t) => {
  const { controller, inputs, attributes } = setup(t, {
    search: "?panel=timeline",
    start: "2026-10-14T00:00",
  })
  assert.equal(controller.selectedDate, null)
  assert.equal(inputs.start_at.value, "2026-10-14T00:00")
  const src = new URL(attributes.src, window.location).searchParams
  assert.equal(src.get("start_at"), "2026-10-14T00:00")
  assert.equal(src.get("end_at"), "2026-10-16T23:59")
})

// A rendered period: three closed <details>, opening one closes the others.
function period(controller, dates) {
  const days = dates.map((date) => ({
    dataset: { day: date, bounds: JSON.stringify({ sw_lat: 1 }) },
    scrollIntoView() {},
    _open: false,
    get open() {
      return this._open
    },
    set open(value) {
      if (value) for (const day of days) day._open = false
      this._open = value
      controller.dayToggled()
    },
  }))
  const frame = controller.visitListFrameTarget
  frame.querySelectorAll = () => days
  frame.querySelector = (selector) =>
    selector.includes("[open]")
      ? days.find((day) => day.open) || null
      : days.find((day) => selector.includes(`"${day.dataset.day}"`)) || null
  return days
}

function dayEvents() {
  const events = []
  for (const name of ["day-expanded", "day-collapsed"]) {
    document.addEventListener(`timeline-feed:${name}`, (event) =>
      events.push([name, event.detail?.day]),
    )
  }
  return events
}

test("opening a day of the period selects it, closing it returns to the period", (t) => {
  const { controller, events } = setup(t, { start: "2026-10-14T00:00" })
  const days = period(controller, ["2026-10-14", "2026-10-15", "2026-10-16"])
  const selected = dayEvents()

  days[1].open = true
  assert.equal(controller.selectedDate, "2026-10-15")
  days[1].open = false
  assert.equal(controller.selectedDate, null)

  assert.deepEqual(selected, [
    ["day-expanded", "2026-10-15"],
    ["day-collapsed", undefined],
  ])
  assert.deepEqual(events, [])
})

test("arrows step through the days of a period", (t) => {
  const { controller, events } = setup(t, { start: "2026-10-14T00:00" })
  period(controller, ["2026-10-14", "2026-10-15", "2026-10-16"])

  pressKey("ArrowRight")
  pressKey("ArrowRight")
  assert.equal(controller.selectedDate, "2026-10-15")
  pressKey("ArrowLeft")
  pressKey("ArrowLeft")
  assert.equal(controller.selectedDate, "2026-10-14")
  assert.deepEqual(events, [])
})

test("replay moving into another day moves the selected day, and only then", (t) => {
  const { controller } = setup(t, { start: "2026-10-14T00:00" })
  period(controller, ["2026-10-14", "2026-10-15"])
  const replayTo = (day) =>
    document.dispatchEvent(
      new CustomEvent("replay:day-changed", { detail: { day } }),
    )

  replayTo("2026-10-15")
  assert.equal(controller.selectedDate, null)

  controller.selectInRange("2026-10-14")
  replayTo("2026-10-15")
  assert.equal(controller.selectedDate, "2026-10-15")
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
  controller.selectedDate = "2026-10-01"
  document.dispatchEvent(
    new CustomEvent("timeline-feed:date-navigated", {
      detail: { startAt: "2026-10-20T00:00", endAt: "2026-10-20T23:59" },
    }),
  )
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

test("Enter in the search field looks through every note; an empty search brings the days back", (t) => {
  const { controller, attributes } = setup(t, {
    search: "?panel=timeline",
    start: "2026-10-14T00:00",
  })
  controller.hasSearchInputTarget = true
  controller.searchInputTarget = { value: " rain " }
  controller.searchNotes()
  assert.equal(attributes.src, "/map/timeline_feeds?q=rain")

  controller.searchInputTarget.value = ""
  controller.searchNotes()
  const src = new URL(attributes.src, window.location).searchParams
  assert.equal(src.get("q"), null)
  assert.equal(src.get("start_at"), "2026-10-14T00:00")
})

test("a period picked in the calendar is applied without a page load", (t) => {
  const { inputs, events, attributes } = setup(t, { search: "?panel=timeline" })
  document.dispatchEvent(
    new CustomEvent("period-picker:range", {
      detail: { startAt: "2026-10-10T00:00:00", endAt: "2026-10-16T23:59:59" },
    }),
  )

  assert.equal(inputs.start_at.value, "2026-10-10T00:00")
  assert.equal(inputs.end_at.value, "2026-10-16T23:59")
  assert.equal(
    window.location.searchParams.get("start_at"),
    "2026-10-10T00:00:00",
  )
  assert.equal(window.location.searchParams.get("date"), null)
  assert.equal(
    new URL(attributes.src, window.location).searchParams.get("end_at"),
    "2026-10-16T23:59",
  )
  assert.deepEqual(
    events.map((event) => [event.startAt, event.endAt]),
    [["2026-10-10T00:00:00", "2026-10-16T23:59:59"]],
  )
})

test("a whole single day picked in the calendar opens like any other day", (t) => {
  const { events } = setup(t, { search: "?panel=timeline" })
  document.dispatchEvent(
    new CustomEvent("period-picker:range", {
      detail: { startAt: "2026-09-03T00:00:00", endAt: "2026-09-03T23:59:59" },
    }),
  )
  assert.deepEqual(
    events.map((event) => event.date),
    ["2026-09-03"],
  )
})

test("part of a day picked in the calendar keeps its exact times", (t) => {
  const { inputs, events, attributes } = setup(t, { search: "?panel=timeline" })
  document.dispatchEvent(
    new CustomEvent("period-picker:range", {
      detail: { startAt: "2026-09-03T09:00:00", endAt: "2026-09-03T18:30:59" },
    }),
  )
  assert.equal(inputs.start_at.value, "2026-09-03T09:00")
  assert.equal(inputs.end_at.value, "2026-09-03T18:30")
  assert.deepEqual(
    events.map((event) => [event.startAt, event.endAt]),
    [["2026-09-03T09:00:00", "2026-09-03T18:30:59"]],
  )
  // The Timeline still reads it as that day.
  assert.equal(
    new URL(attributes.src, window.location).searchParams.get("start_at"),
    "2026-09-03T00:00:00",
  )
})

function dayFrameStream() {
  return Object.assign(
    new Event("turbo:before-stream-render", { cancelable: true }),
    {
      detail: {
        newStream: {
          getAttribute: (name) =>
            ({ target: "timeline-feed-frame", action: "update" })[name],
        },
      },
    },
  )
}

test("a bulk action inside a period re-reads the period instead of leaving one day", (t) => {
  const { controller } = setup(t, { start: "2026-10-14T00:00" })
  let reloads = 0
  controller.visitListFrameTarget.reload = () => {
    reloads += 1
  }
  const refetches = []
  document.addEventListener("visit:updated", () => refetches.push(true))

  const stream = dayFrameStream()
  document.dispatchEvent(stream)

  assert.equal(stream.defaultPrevented, true)
  assert.equal(reloads, 1)
  assert.equal(refetches.length, 1)
})

test("a bulk action on a single day still takes the re-rendered day", (t) => {
  const { controller } = setup(t)
  let reloads = 0
  controller.visitListFrameTarget.reload = () => {
    reloads += 1
  }

  const stream = dayFrameStream()
  document.dispatchEvent(stream)

  assert.equal(stream.defaultPrevented, false)
  assert.equal(reloads, 0)
})

test("a whole day stays a single day when the clocks go back", (t) => {
  // October 25, 2026 is 25 hours long in zones that leave summer time that
  // night. Run the test in one of them, wherever the suite runs.
  const zone = process.env.TZ
  process.env.TZ = "Europe/Berlin"
  t.after(() => {
    if (zone === undefined) delete process.env.TZ
    else process.env.TZ = zone
  })
  assert.equal(
    new Date("2026-10-25T23:59") - new Date("2026-10-25T00:00") > 24 * 3600000,
    true,
  )
  const { controller } = setup(t, {
    start: "2026-10-25T00:00",
    end: "2026-10-25T23:59",
  })
  assert.equal(controller.periodSpansDays(), false)
})

test("two calendar days are a period", (t) => {
  const { controller } = setup(t, {
    start: "2026-10-25T00:00",
    end: "2026-10-26T23:59",
  })
  assert.equal(controller.periodSpansDays(), true)
})

test("a timed period of over a day that passes midnight is a period", (t) => {
  const { controller } = setup(t, {
    start: "2026-11-05T10:00",
    end: "2026-11-06T10:30",
  })
  assert.equal(controller.periodSpansDays(), true)
})

test("a night across midnight is still read as one day", (t) => {
  const { controller } = setup(t, {
    start: "2026-11-05T22:00",
    end: "2026-11-06T06:00",
  })
  assert.equal(controller.periodSpansDays(), false)
})

function rowStream(target) {
  return Object.assign(
    new Event("turbo:before-stream-render", { cancelable: true }),
    {
      detail: {
        newStream: {
          getAttribute: (name) => ({ target, action: "replace" })[name],
        },
      },
    },
  )
}

test("a visit listed on both of its days re-reads the period when its row changes", (t) => {
  const { controller } = setup(t, { start: "2026-10-14T00:00" })
  let reloads = 0
  controller.visitListFrameTarget.reload = () => {
    reloads += 1
  }
  document.querySelectorAll = (selector) =>
    selector === '[id="visit_entry_7"]' ? [{}, {}] : []

  const twice = rowStream("visit_entry_7")
  document.dispatchEvent(twice)
  const once = rowStream("visit_entry_8")
  document.dispatchEvent(once)

  assert.equal(twice.defaultPrevented, true)
  assert.equal(once.defaultPrevented, false)
  assert.equal(reloads, 1)
})
