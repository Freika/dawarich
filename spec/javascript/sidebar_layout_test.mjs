import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/sidebar_layout.js",
    import.meta.url,
  ),
  "utf8",
)
const { syncSidebarLayout } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function elements(panelClasses = [], containerClasses = []) {
  const classes = new Set(containerClasses)
  const dataset = { sidebarLayoutReady: "true" }
  const events = []
  const panel = {
    classList: { contains: (name) => panelClasses.includes(name) },
  }
  const container = {
    parentElement: { dataset },
    classList: {
      contains: (name) => classes.has(name),
      toggle(name, enabled) {
        events.push({ name, ready: dataset.sidebarLayoutReady })
        if (enabled) classes.add(name)
        else classes.delete(name)
      },
    },
    getBoundingClientRect() {
      events.push({ name: "layout", ready: dataset.sidebarLayoutReady })
      assert.equal(classes.has("panel-open"), panelClasses.includes("open"))
      assert.equal(
        classes.has("panel-timeline-expanded"),
        panelClasses.includes("open") &&
          panelClasses.includes("timeline-expanded"),
      )
      return {}
    },
  }
  return { panel, container, dataset, events }
}

test("an open panel applies panel-open", () => {
  const { panel, container } = elements(["open"])
  syncSidebarLayout(panel, container)
  assert.equal(container.classList.contains("panel-open"), true)
  assert.equal(container.classList.contains("panel-timeline-expanded"), false)
})

test("an open expanded Timeline applies both layout classes", () => {
  const { panel, container } = elements(["open", "timeline-expanded"])
  syncSidebarLayout(panel, container)
  assert.equal(container.classList.contains("panel-open"), true)
  assert.equal(container.classList.contains("panel-timeline-expanded"), true)
})

test("a closed expanded Timeline clears both layout classes", () => {
  const { panel, container } = elements(
    ["timeline-expanded"],
    ["panel-open", "panel-timeline-expanded"],
  )
  syncSidebarLayout(panel, container)
  assert.equal(container.classList.contains("panel-open"), false)
  assert.equal(container.classList.contains("panel-timeline-expanded"), false)
})

test("a missing panel does not throw", () => {
  const { container } = elements()
  assert.doesNotThrow(() => syncSidebarLayout(null, container, true))
})

test("a missing container does not throw", () => {
  const { panel } = elements()
  assert.doesNotThrow(() => syncSidebarLayout(panel, null, true))
})

test("initial sync clears snapshot readiness before toggles and layout", () => {
  const { panel, container, dataset, events } = elements(
    ["open"],
    ["panel-timeline-expanded"],
  )
  syncSidebarLayout(panel, container, true)
  assert.deepEqual(events, [
    { name: "panel-open", ready: undefined },
    { name: "panel-timeline-expanded", ready: undefined },
    { name: "layout", ready: undefined },
  ])
  assert.equal(dataset.sidebarLayoutReady, "true")
})
