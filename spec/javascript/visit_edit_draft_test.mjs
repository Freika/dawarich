import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const sources = await Promise.all(
  [
    "maps_maplibre/components/visit_form_draft",
    "controllers/visit_creation_v2_controller",
  ].map(async (file) =>
    readFile(
      new URL(`../../app/javascript/${file}.js`, import.meta.url),
      "utf8",
    ),
  ),
)

const field = (value = "") => ({ value, addEventListener() {} })

function buildEditor() {
  const requests = []
  const context = vm.createContext({
    Controller: class {},
    AbortController,
    URLSearchParams,
    setTimeout() {},
    requestAnimationFrame: () => 0,
    translate: (key) => key,
    document: { querySelector: () => null, dispatchEvent() {} },
    CustomEvent: class {},
    VisitPlaceSearch: class {
      constructor(...args) {
        this.options = args[5]
      }
      distanceMeters() {
        return 10
      }
      close() {}
    },
    FormData: class {
      constructor(fields) {
        this.fields = fields
      }
      get(key) {
        return this.fields[key].value
      }
    },
    fetch: async (url, options) => {
      requests.push({ url, ...options })
      return {
        ok: true,
        json: async () => ({
          places: [{ id: 9, name: "Nearby Cafe", has_visits: true }],
        }),
      }
    },
  })
  vm.runInContext(
    sources
      .map((source) =>
        source
          .replace(/^import .*\n/gm, "")
          .replace("export class VisitFormDraft", "class VisitFormDraft")
          .replace(
            "export default class extends Controller",
            "globalThis.VisitEditor = class extends Controller",
          ),
      )
      .join("\n"),
    context,
  )
  const editor = new context.VisitEditor()
  for (const name of [
    "nameInput",
    "latitudeInput",
    "longitudeInput",
    "startTimeInput",
    "endTimeInput",
    "placeIdInput",
  ]) {
    editor[`${name}Target`] = field()
  }
  editor.placeNameTarget = {}
  editor.placeSearchTarget = {}
  editor.modalTarget = { classList: { add() {} }, showModal() {}, close() {} }
  editor.timezoneValue = "UTC"
  editor.addMarker = () => {}
  editor.showToast = () => {}
  editor.close = () => {}
  editor.formTarget = Object.fromEntries(
    Object.entries({
      name: "nameInput",
      latitude: "latitudeInput",
      longitude: "longitudeInput",
      started_at: "startTimeInput",
      ended_at: "endTimeInput",
      place_id: "placeIdInput",
    }).map(([key, target]) => [key, editor[`${target}Target`]]),
  )
  return { editor, requests }
}

for (const kind of ["placeless", "suggested", "legacy Area"]) {
  test(`editing only the times of a ${kind} visit sends no place_id`, async () => {
    const { editor, requests } = buildEditor()
    editor.openForEdit({
      id: 12,
      place: null,
      name: "",
      status: kind === "suggested" ? "suggested" : "confirmed",
      area:
        kind === "legacy Area" ? { id: 3, latitude: 52, longitude: 13 } : null,
      center: { latitude: 52, longitude: 13 },
      started_at: "2026-01-01T10:00:00Z",
      ended_at: "2026-01-01T11:00:00Z",
    })
    await new Promise(setImmediate)
    editor.startTimeInputTarget.value = "2026-01-01T10:15"
    editor.endTimeInputTarget.value = "2026-01-01T11:15"
    await editor.submit({ preventDefault() {} })
    const update = requests.find((request) => request.method === "PATCH")
    assert.ok(update)
    const payload = JSON.parse(update.body).visit
    assert.equal(Object.hasOwn(payload, "place_id"), false)
    assert.equal(payload.name, "")
    assert.equal(payload.started_at, "2026-01-01T10:15:00.000Z")
    assert.equal(payload.ended_at, "2026-01-01T11:15:00.000Z")
    assert.equal(requests.length, 1)
    editor.draftForm.search.options.onSelect({ id: 7, name: "Chosen Cafe" })
    await editor.submit({ preventDefault() {} })
    assert.equal(JSON.parse(requests.at(-1).body).visit.place_id, 7)
    assert.equal(editor.nameInputTarget.value, "")
  })
}

test("editing a placed visit prefills only its custom name", () => {
  const { editor } = buildEditor()
  editor.openForEdit({
    id: 12,
    place: { id: 4, name: "Old Cafe", latitude: 52, longitude: 13 },
    name: "Old Cafe",
    custom_name: null,
    started_at: "2026-01-01T10:00:00Z",
    ended_at: "2026-01-01T11:00:00Z",
  })
  assert.equal(editor.nameInputTarget.value, "")
  assert.equal(editor.nameInputTarget.required, false)
  editor.openForEdit({
    id: 13,
    place: { id: 4, name: "Old Cafe", latitude: 52, longitude: 13 },
    name: "Grandma",
    custom_name: "Grandma",
    started_at: "2026-01-01T10:00:00Z",
    ended_at: "2026-01-01T11:00:00Z",
  })
  assert.equal(editor.nameInputTarget.value, "Grandma")
})

test("choosing a new Place while editing does not resend the old Place name", async () => {
  const { editor, requests } = buildEditor()
  editor.openForEdit({
    id: 12,
    place: { id: 4, name: "Old Cafe", latitude: 52, longitude: 13 },
    name: "Old Cafe",
    custom_name: null,
    started_at: "2026-01-01T10:00:00Z",
    ended_at: "2026-01-01T11:00:00Z",
  })
  editor.draftForm.search.options.onSelect({ id: 7, name: "New Cafe" })
  await editor.submit({ preventDefault() {} })
  const payload = JSON.parse(requests.at(-1).body).visit
  assert.equal(payload.place_id, 7)
  assert.notEqual(payload.name, "Old Cafe")
})

test("creating a visit keeps the name required", () => {
  const { editor } = buildEditor()
  editor.nameInputTarget.required = false
  editor.open(52, 13, null, { placeId: 4, name: "Cafe" })
  assert.equal(editor.nameInputTarget.required, true)
})
