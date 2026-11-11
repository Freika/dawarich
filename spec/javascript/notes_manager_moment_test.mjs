import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/notes_manager.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { NotesManager } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

// A map with nothing under the click, showing the given period.
function manager(t, { start, end, selectedDay }) {
  const original = globalThis.document
  globalThis.document = { addEventListener() {}, removeEventListener() {} }
  t.after(() => {
    globalThis.document = original
  })
  return new NotesManager({
    map: { getLayer: () => null, queryRenderedFeatures: () => [] },
    startDateValue: start,
    endDateValue: end,
    _highlightedDay: selectedDay,
  })
}

const localNoon = (day) => new Date(`${day}T12:00:00`).toISOString()

test("a note written with a past day selected belongs to that day", (t) => {
  const notes = manager(t, {
    start: "2020-03-01T00:00:00+00:00",
    end: "2020-03-31T23:59:59+00:00",
    selectedDay: "2020-03-14",
  })
  assert.equal(notes.momentAt({ x: 1, y: 1 }), localNoon("2020-03-14"))
})

test("with today selected, or no day selected in a period, the note is about now", (t) => {
  const today = new Date().toLocaleDateString("en-CA")
  const period = {
    start: "2020-03-01T00:00:00+00:00",
    end: "2020-03-31T23:59:59+00:00",
  }
  assert.equal(
    manager(t, { ...period, selectedDay: today }).momentAt({ x: 1, y: 1 }),
    undefined,
  )
  assert.equal(
    manager(t, { ...period, selectedDay: null }).momentAt({ x: 1, y: 1 }),
    undefined,
  )
})
