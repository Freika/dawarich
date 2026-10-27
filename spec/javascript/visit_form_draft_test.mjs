import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

async function load(file, bindings) {
  const source = await readFile(
    new URL(`../../app/javascript/maps_maplibre/${file}.js`, import.meta.url),
    "utf8",
  ).catch(() => "")
  const context = vm.createContext({
    ...bindings,
    AbortController,
    URLSearchParams,
  })
  vm.runInContext(
    source.replace(/^import .*\n/gm, "").replace(/export /g, "") +
      "\nglobalThis.exports = { " +
      (file.endsWith("visit_form_draft")
        ? "VisitFormDraft"
        : "selectionVisitDraft, prefillVisitFromClick") +
      " }",
    context,
  )
  return context.exports
}
const field = (value = "") => ({
  value,
  addEventListener(type, handler) {
    this[type] = handler
  },
})
const place = {
  id: 2,
  name: "Cafe",
  latitude: 52,
  longitude: 13,
  has_visits: true,
}
function controller() {
  return {
    apiKeyValue: "test",
    latitudeInputTarget: field(52),
    longitudeInputTarget: field(13),
    nameInputTarget: field(),
    placeIdInputTarget: field(),
    placeNameTarget: { textContent: "" },
    placeSearchTarget: {},
    startTimeInputTarget: field("now"),
    endTimeInputTarget: field("later"),
    formatDateTime: (date) => date.toISOString(),
    addMarker() {},
  }
}
class Search {
  constructor(...args) {
    this.options = args[5]
  }
  distanceMeters(lat) {
    return lat === 52 ? 20 : 200
  }
  close() {}
}
async function formModule(fetch) {
  return load("components/visit_form_draft", {
    fetch,
    VisitPlaceSearch: Search,
    translate: (key) => key,
  })
}

test("async context preselects the nearest visited Place and never overwrites a typed name", async () => {
  const { VisitFormDraft } = await formModule(async () => ({
    ok: true,
    json: async () => ({
      places: [{ ...place, id: 1, name: "Unused", has_visits: false }, place],
    }),
  }))
  const c = controller()
  const draft = new VisitFormDraft(c)
  await draft.open()
  assert.equal(c.placeIdInputTarget.value, 2)
  assert.equal(c.nameInputTarget.value, "Cafe")
  c.nameInputTarget.value = "My name"
  await draft.open()
  assert.equal(c.nameInputTarget.value, "My name")
})

test("context uses a reverse geocoded name only without a nearby visited Place", async () => {
  const { VisitFormDraft } = await formModule(async () => ({
    ok: true,
    json: async () => ({
      places: [
        { ...place, latitude: 53 },
        { name: "Geocoded cafe", latitude: 52, longitude: 13 },
      ],
    }),
  }))
  const c = controller()
  await new VisitFormDraft(c).open()
  assert.equal(c.placeIdInputTarget.value, "")
  assert.equal(c.nameInputTarget.value, "Geocoded cafe")
})

test("late history preserves each edited time and ignores a closed form", async () => {
  const { VisitFormDraft } = await formModule(async () => ({
    ok: true,
    json: async () => ({ places: [] }),
  }))
  const c = controller()
  const form = new VisitFormDraft(c)
  await form.open()
  c.startTimeInputTarget.value = "user time"
  c.startTimeInputTarget.input()
  form.applyHistory({
    lat: 52,
    lng: 13,
    startedAt: "2026-01-01T10:00:00Z",
    endedAt: "2026-01-01T11:00:00Z",
  })
  assert.equal(c.startTimeInputTarget.value, "user time")
  assert.equal(c.endTimeInputTarget.value, "2026-01-01T11:00:00.000Z")
  form.close()
  form.applyHistory({
    lat: 54,
    lng: 15,
    startedAt: "2026-01-02",
    endedAt: "2026-01-03",
  })
  assert.equal(c.latitudeInputTarget.value, 52)
})

test("edit context retains the attributed Place and Visit Name until the picker changes", async () => {
  const { VisitFormDraft } = await formModule(() => {
    throw new Error("edit must not preselect")
  })
  const c = controller()
  c.nameInputTarget.value = "Visit name"
  const form = new VisitFormDraft(c)
  await form.open(place)
  assert.equal(c.placeIdInputTarget.value, 2)
  assert.equal(c.nameInputTarget.value, "Visit name")
  form.search.options.onSelect({ ...place, id: 4, name: "Chosen" })
  assert.equal(c.placeIdInputTarget.value, 4)
  assert.equal(c.nameInputTarget.value, "Visit name")
  c.nameInputTarget.value = ""
  await form.open(place)
  assert.equal(c.nameInputTarget.value, "Cafe")
})

test("an obsolete context response cannot replace a user's Place choice", async () => {
  let resolve
  const { VisitFormDraft } = await formModule(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  const c = controller()
  const form = new VisitFormDraft(c)
  const pending = form.open()
  form.search.options.onSelect({ ...place, id: 8, name: "Chosen" })
  resolve({ ok: true, json: async () => ({ places: [place] }) })
  await pending
  assert.equal(c.placeIdInputTarget.value, 8)
  assert.equal(c.nameInputTarget.value, "Chosen")
})

test("history clears an automatic Place preselection that no longer matches the stay", async () => {
  let requests = 0
  const { VisitFormDraft } = await formModule(async () => ({
    ok: true,
    json: async () => ({ places: requests++ === 0 ? [place] : [] }),
  }))
  const c = controller()
  const form = new VisitFormDraft(c)
  await form.open()
  assert.equal(c.placeIdInputTarget.value, 2)
  form.applyHistory({
    lat: 53,
    lng: 14,
    startedAt: "2026-01-01",
    endedAt: "2026-01-02",
  })
  await form.loadContext()
  assert.equal(c.placeIdInputTarget.value, "")
  assert.equal(c.placeNameTarget.textContent, "visits.choose_place")
})
