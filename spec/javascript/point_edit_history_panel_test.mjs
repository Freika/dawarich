import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const stripImports = (value) =>
  value.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const panel = await read("maps_maplibre/editing/point_edit_history_panel.js")
const formatHelpers = await read("maps_maplibre/utils/format_helpers.js")
const translations = {
  "messages.point_label": "Point #%{id}",
}
const stubs = `const translate = (key, values = {}) =>
  (${JSON.stringify(translations)}[key] || key).replace(/%\\{(\\w+)\\}/g, (_m, name) => values[name])`
const { historyItems, PointEditHistoryPanel } = await import(
  `data:text/javascript;base64,${Buffer.from(
    [stubs, stripImports(formatHelpers), stripImports(panel)].join("\n"),
  ).toString("base64")}`
)

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

  const items = historyItems(history, { distanceUnit: "km" })

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
  const history = { entries: [entry(9, 1)], undone: [] }

  const [item] = historyItems(history, { distanceUnit: "km" })

  assert.equal(item.distance, "100 m")
  assert.equal(item.pointLabel, "Point #9")
})

test("uses the user's distance unit", () => {
  const history = { entries: [entry(9, 1)], undone: [] }

  const [item] = historyItems(history, { distanceUnit: "mi" })

  assert.match(item.distance, /ft$/)
})

test("the close button asks to close the panel", () => {
  let closed = 0
  const panel = new PointEditHistoryPanel({
    onClose: () => {
      closed += 1
    },
  })

  panel._onClick({
    target: {
      closest: () => ({ dataset: { action: "close" }, disabled: false }),
    },
  })

  assert.equal(closed, 1)
})
