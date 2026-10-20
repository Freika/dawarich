import test from "node:test"
import assert from "node:assert/strict"
import * as presentation from "../../assets/js/insights/presentation.js"
const { InsightsCalendar, InsightsRace, InsightsUpdate } = presentation

function node(extra = {}) {
  const classes = new Set(["hidden"])
  return {
    dataset: {}, style: {}, listeners: new Map(), textContent: "",
    classList: { add: (v) => classes.add(v), remove: (v) => classes.delete(v), contains: (v) => classes.has(v) },
    addEventListener(name, callback) { this.listeners.set(name, callback) },
    removeEventListener(name, callback) { if (this.listeners.get(name) === callback) this.listeners.delete(name) },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 300 }),
    setAttribute(name, value) { this[name] = value },
    offsetWidth: 80, offsetHeight: 20,
    ...extra,
  }
}

test("native calendar centers the source active date and owns safe tooltip listeners through teardown", async () => {
  assert.equal(typeof InsightsCalendar.mounted, "function")
  const scroller = node({ scrollLeft: 0, clientWidth: 200 })
  const cell = node({ dataset: { date: "2024-03-05", label: "Di., 5. März", country: "<b>Germany</b>", distance: "2.3 km" }, getBoundingClientRect: () => ({ left: 180, top: 80, width: 10 }) })
  cell.closest = () => cell
  const tooltip = node({ parentElement: node() })
  const date = node(), detail = node()
  const elements = { "[data-native-calendar-scroller]": scroller, "[data-native-calendar-tooltip]": tooltip, "[data-native-tooltip-date]": date, "[data-native-tooltip-detail]": detail, '[data-date="2024-03-05"]': cell }
  const root = node({ dataset: { nativeTargetDate: "2024-03-05", nativeNoData: "Keine Daten" }, querySelector: (key) => elements[key] })
  const owner = { ...InsightsCalendar, el: root }
  await InsightsCalendar.mounted.call(owner)
  assert.equal(scroller.scrollLeft, 80)
  root.listeners.get("mouseover")({ target: cell })
  assert.equal(date.textContent, "Di., 5. März")
  assert.equal(detail.textContent, "<b>Germany</b> · 2.3 km")
  assert.equal(tooltip.classList.contains("hidden"), false)
  root.listeners.get("mouseleave")()
  assert.equal(tooltip.classList.contains("hidden"), true)
  assert.equal(typeof InsightsCalendar.updated, "function")
  InsightsCalendar.updated.call(owner)
  assert.equal(scroller.scrollLeft, 80)
  InsightsCalendar.destroyed.call(owner)
  assert.equal(root.listeners.size, 0)
})

test("native distance race retains localized SVG hover values and removes its owned listeners", async () => {
  assert.equal(typeof InsightsRace.mounted, "function")
  const scroller = node({ scrollLeft: 0, scrollWidth: 720, clientWidth: 300 })
  const svg = node({ parentElement: scroller, getScreenCTM: () => ({ inverse: () => ({}) }), createSVGPoint() { return { x: 0, y: 0, matrixTransform() { return this } } } })
  const hit = node(), hover = node(), line = node(), tooltip = node({ parentElement: node() })
  const date = node(), current = node(), previous = node()
  const elements = { "[data-native-race-svg]": svg, "[data-native-race-hit]": hit, "[data-native-race-hover]": hover, "[data-native-race-hover-line]": line, "[data-native-race-tooltip]": tooltip, "[data-native-tooltip-date]": date, "[data-native-tooltip-current]": current, "[data-native-tooltip-previous]": previous }
  const root = node({ dataset: { nativeCurrent: "[1234,2345]", nativePrevious: "[1000,2000]", nativeYear: "2024", nativeUnit: "km" }, ownerDocument: { documentElement: { lang: "de" } }, querySelector: (key) => elements[key] })
  const owner = { ...InsightsRace, el: root }
  await InsightsRace.mounted.call(owner)
  hit.listeners.get("mousemove")({ clientX: 46, clientY: 80 })
  assert.equal(current.textContent, "2024: 1.234 km")
  assert.equal(previous.textContent, "2023: 1.000 km")
  assert.equal(hover.visibility, "visible")
  assert.equal(tooltip.classList.contains("hidden"), false)
  hit.listeners.get("mouseleave")()
  assert.equal(hover.visibility, "hidden")
  assert.equal(typeof InsightsRace.updated, "function")
  root.dataset.nativeCurrent = "[3456,4567]"
  InsightsRace.updated.call(owner)
  hit.listeners.get("mousemove")({ clientX: 46, clientY: 80 })
  assert.equal(current.textContent, "2024: 3.456 km")
  InsightsRace.destroyed.call(owner)
  assert.equal(hit.listeners.size, 0)
})

test("native Insights presentation ignores library loading completed after departure", async () => {
  const root = node({ dataset: {}, querySelector: () => null })
  const owner = { ...InsightsCalendar, el: root }
  const mounting = owner.mounted()
  assert.equal(mounting instanceof Promise, true)
  owner.destroyed()
  await mounting
  assert.equal(root.listeners.size, 0)
})

test("native Insights refresh cancels HTTP navigation and releases its click listener", () => {
  assert.equal(typeof InsightsUpdate?.mounted, "function")
  const root = node()
  const owner = { ...InsightsUpdate, el: root }
  owner.mounted()
  let prevented = false
  root.listeners.get("click")({ preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  owner.destroyed()
  assert.equal(root.listeners.size, 0)
})
