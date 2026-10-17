import assert from "node:assert/strict"
import test from "node:test"
import {
  historyItems,
  PointEditHistoryPanel,
} from "../../app-phoenix/assets/js/map/edit/history_panel.js"

const translations = { "messages.point_label": "Point #%{id}" }
const translate = (key, values = {}) =>
  (translations[key] || key).replace(/%\{(\w+)\}/g, (_m, name) => values[name])

const entry = (pointId, at) => ({
  pointId,
  from: { longitude: 13.4, latitude: 52.52 },
  to: { longitude: 13.4, latitude: 52.5209 },
  at,
})

test("lists what can be redone first, then the edits made, newest first", () => {
  const history = {
    entries: [entry(1, 1), entry(2, 2)],
    undone: [entry(4, 4), entry(3, 3)],
  }
  const items = historyItems(history, { distanceUnit: "km", translate })
  assert.deepEqual(
    items.map((item) => [item.entry.pointId, item.undone, item.current]),
    [
      [4, true, false],
      [3, true, false],
      [2, false, true],
      [1, false, false],
    ],
  )
})

test("labels each edit with how far it moved and which point it was", () => {
  const [item] = historyItems(
    { entries: [entry(9, 1)], undone: [] },
    { distanceUnit: "km", translate },
  )
  assert.equal(item.distance, "100 m")
  assert.equal(item.pointLabel, "Point #9")
})

test("uses the user's distance unit", () => {
  const [item] = historyItems(
    { entries: [entry(9, 1)], undone: [] },
    { distanceUnit: "mi", translate },
  )
  assert.match(item.distance, /ft$/)
})

function element(tag) {
  const listeners = new Map()
  const node = {
    tag,
    children: [],
    dataset: {},
    attributes: {},
    textContent: "",
    disabled: false,
    className: "",
    addEventListener: (type, fn) => listeners.set(type, fn),
    setAttribute(name, value) {
      node.attributes[name] = value
    },
    append(...children) {
      node.children.push(...children)
    },
    replaceChildren(...children) {
      node.children = children
    },
    remove() {
      node.removed = true
    },
    closest: () => node,
    listeners,
  }
  return node
}

test("history panel renders rows and routes undo, redo, travel and close", () => {
  const calls = []
  const panel = new PointEditHistoryPanel({
    document: { createElement: element },
    translate,
    distanceUnit: "km",
    onUndo: () => calls.push("undo"),
    onRedo: () => calls.push("redo"),
    onTravel: (target) => calls.push(["travel", target.pointId]),
    onClose: () => calls.push("close"),
  })
  const container = panel.onAdd()
  panel.render({
    entries: [entry(1, 1), entry(2, 2)],
    undone: [],
    size: 2,
    limit: 50,
    canUndo: true,
    canRedo: false,
    busy: false,
  })
  const buttons = (node) =>
    node.tag === "button" ? [node] : node.children.flatMap(buttons)
  const [undo, redo, close, newest, oldest] = buttons(container)
  assert.equal(redo.disabled, true)
  const click = (target) => container.listeners.get("click")({ target })
  click(redo)
  click(undo)
  click(oldest)
  click(close)
  assert.deepEqual(calls, ["undo", ["travel", 1], "close"])
  assert.equal(newest.attributes["aria-current"], "step")
  panel.onRemove()
  assert.equal(container.removed, true)
})
