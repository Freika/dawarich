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
function manager(t, { start, end, selectedDay, timezone }) {
  const original = globalThis.document
  globalThis.document = { addEventListener() {}, removeEventListener() {} }
  t.after(() => {
    globalThis.document = original
  })
  return new NotesManager({
    map: { getLayer: () => null, queryRenderedFeatures: () => [] },
    startDateValue: start,
    endDateValue: end,
    timezoneValue: timezone,
    timelineBridge: { highlightedDay: selectedDay },
  })
}

const period = {
  start: "2020-03-01T00:00:00+00:00",
  end: "2020-03-31T23:59:59+00:00",
}

test("a note written with a past day selected is about noon of that day, on the account's clock", (t) => {
  const notes = manager(t, { ...period, selectedDay: "2020-03-14" })
  // No zone in the value: the server reads it in the account's time zone.
  assert.equal(notes.momentAt({ x: 1, y: 1 }), "2020-03-14T12:00")
})

test("with today selected, or no day selected in a period, the note is about now", (t) => {
  // Today by the account's clock, not the browser's. These two zones are
  // 25 hours apart, so the browser's own date matches one of them at most.
  for (const timezone of ["Pacific/Kiritimati", "Pacific/Niue"]) {
    const today = new Date().toLocaleDateString("en-CA", { timeZone: timezone })
    assert.equal(
      manager(t, { ...period, selectedDay: today, timezone }).momentAt({
        x: 1,
        y: 1,
      }),
      undefined,
    )
  }
  assert.equal(
    manager(t, { ...period, selectedDay: null }).momentAt({ x: 1, y: 1 }),
    undefined,
  )
})
