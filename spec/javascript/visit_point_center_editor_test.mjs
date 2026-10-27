import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/visit_creation_v2_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
)
  .replace(/^import.*\n/gm, "")
  .replace(
    "export default class extends Controller",
    "globalThis.VisitEditor = class extends Controller",
  )
const context = {
  Controller: class {},
  document: { querySelector: () => null },
  setTimeout: () => {},
  translate: (key) => key,
}
vm.createContext(context)
vm.runInContext(source, context)

function edit(visit) {
  const editor = new context.VisitEditor()
  editor.nameInputTarget = {}
  editor.latitudeInputTarget = {}
  editor.longitudeInputTarget = {}
  editor.startTimeInputTarget = {}
  editor.endTimeInputTarget = {}
  editor.modalTarget = { classList: { add() {} } }
  editor.formatDateTime = () => "2026-09-04T12:00"
  editor.addMarker = (lat, lng) => {
    editor.position = [lng, lat]
  }
  editor.openForEdit({
    id: 1,
    started_at: "2026-09-04T12:00:00Z",
    ended_at: "2026-09-04T13:00:00Z",
    ...visit,
  })
  return editor
}

test("visit editor uses the point center for an unplaced visit", () => {
  const editor = edit({
    place: null,
    center: { latitude: 52.51, longitude: 13.41 },
  })
  assert.equal(editor.latitudeInputTarget.value, 52.51)
  assert.equal(editor.longitudeInputTarget.value, 13.41)
  assert.deepEqual(editor.position, [13.41, 52.51])
})

test("visit editor preserves Place and Area priority and real zero centers", () => {
  const center = { latitude: 0, longitude: 0 }
  const place = { latitude: 51, longitude: 12 }
  const area = { latitude: 50, longitude: 11 }
  assert.deepEqual(edit({ place, area, center }).position, [12, 51])
  assert.deepEqual(edit({ area, center }).position, [11, 50])
  assert.deepEqual(edit({ center }).position, [0, 0])
})
