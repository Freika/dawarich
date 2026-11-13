import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/segment_mode_editor_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { default: SegmentModeEditor } = await import(
  `data:text/javascript;base64,${Buffer.from(
    `class Controller {}\n${withoutImports}`,
  ).toString("base64")}`
)

// Two rows of track 7, connected to a stub document that delivers the map's
// hover events the way TrackSelection dispatches them.
function rowsOfTrack(t) {
  const listeners = {}
  const original = globalThis.document
  globalThis.document = {
    addEventListener: (name, handler) => {
      listeners[name] ||= []
      listeners[name].push(handler)
    },
    removeEventListener() {},
  }
  t.after(() => {
    globalThis.document = original
  })

  const rows = [11, 12].map((segmentId) => {
    const classes = new Set()
    const row = new SegmentModeEditor()
    row.segmentIdValue = segmentId
    row.trackIdValue = 7
    row.element = {
      classList: {
        toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
        contains: (name) => classes.has(name),
      },
      addEventListener() {},
      removeEventListener() {},
    }
    row.connect()
    return row
  })
  const fromMap = (type, detail) => {
    for (const handler of listeners[type] || []) handler({ type, detail })
  }
  const highlighted = () =>
    rows.map((row) => row.element.classList.contains("highlighted"))
  return { fromMap, highlighted }
}

test("hovering a segment on the map highlights only its row", (t) => {
  const { fromMap, highlighted } = rowsOfTrack(t)

  fromMap("dawarich:segment-hover", { trackId: 7, segmentId: 12 })

  assert.deepEqual(highlighted(), [false, true])
})

test("leaving the track's segments on the map clears the highlight", (t) => {
  const { fromMap, highlighted } = rowsOfTrack(t)
  fromMap("dawarich:segment-hover", { trackId: 7, segmentId: 12 })

  // The map does not know which segment it left, only the track.
  fromMap("dawarich:segment-unhover", { trackId: 7 })

  assert.deepEqual(highlighted(), [false, false])
})

test("another track's hover leaves these rows alone", (t) => {
  const { fromMap, highlighted } = rowsOfTrack(t)
  fromMap("dawarich:segment-hover", { trackId: 7, segmentId: 11 })

  fromMap("dawarich:segment-unhover", { trackId: 8 })

  assert.deepEqual(highlighted(), [true, false])
})
