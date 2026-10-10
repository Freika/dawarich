import assert from "node:assert/strict"
import { test } from "node:test"
import {
  bindGalleryControls,
  saveGuard,
  saveRecipe,
  sidecarDistance,
} from "../../app-phoenix/assets/js/poster/gallery_controls.js"

const strings = {
  no_location_data: "No location data.",
  no_tracks_in_frame: "No tracks inside the frame.",
  frame_too_wide: "Wider than the largest poster.",
  gallery_without_flights: "No flight overlays.",
  queued: "Queued",
  untitled: "Unbenannter Poster",
}

const bounds = (south, north, west = 13.3, east = 13.5) => ({
  getSouth: () => south,
  getNorth: () => north,
  getWest: () => west,
  getEast: () => east,
})

test("save guard mirrors the server frame, distance and flight rules", () => {
  const center = { lat: 52.52, lng: 13.405 }
  const near = bounds(52.5, 52.54)
  assert.deepEqual(
    saveGuard({ data: { guardCoords: [] }, center, bounds: near }, strings),
    {
      disabled: true,
      message: "No location data.",
    },
  )
  assert.deepEqual(
    saveGuard(
      { data: { guardCoords: [[2.35, 48.85]] }, center, bounds: near },
      strings,
    ),
    { disabled: true, message: "No tracks inside the frame." },
  )
  assert.deepEqual(
    saveGuard(
      {
        data: { guardCoords: [[13.41, 52.52]], flightsOmitted: true },
        center,
        bounds: near,
      },
      strings,
    ),
    { disabled: false, message: "No flight overlays." },
  )
  const world = bounds(-60, 70, -170, 170)
  assert.deepEqual(
    saveGuard(
      { data: { guardCoords: [[13.41, 52.52]] }, center, bounds: world },
      strings,
    ),
    { disabled: false, message: "Wider than the largest poster." },
  )
  assert.equal(sidecarDistance(bounds(52.52, 52.5201)), 500)
  assert.equal(sidecarDistance(world), 5_000_000)
  assert.equal(sidecarDistance(near), 6679)
})

test("the saved recipe keeps Rails' string form fields and placeholder name", () => {
  const recipe = saveRecipe({
    state: {
      title: "  ",
      themeKey: "noir",
      opacity: 40,
      width: 150,
      data: {
        range: { startAt: "2026-10-01T00:00", endAt: "2026-10-02T00:00" },
      },
    },
    center: { lat: 52.52, lng: 13.405 },
    bounds: bounds(52.5, 52.54),
    trackSource: "routes",
    strings,
  })
  assert.deepEqual(recipe, {
    name: "Unbenannter Poster",
    title: "",
    theme: "noir",
    lat: "52.52",
    lon: "13.405",
    distance: "6679",
    start_at: "2026-10-01T00:00",
    end_at: "2026-10-02T00:00",
    source: "routes",
    route_opacity: "40",
    route_width: "150",
  })
})

function element(props = {}) {
  const target = new EventTarget()
  const classes = new Set(props.classes ?? [])
  return Object.assign(target, {
    disabled: false,
    textContent: "",
    classList: {
      toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
      contains: (name) => classes.has(name),
    },
    ...props,
  })
}

test("save to gallery pushes one recipe per click and waits for the server reply", () => {
  const save = element()
  const notice = element({ classes: ["hidden"] })
  const nodes = { save, "save-notice": notice }
  const pushes = []
  const statuses = []
  const studio = {
    map: {
      getCenter: () => ({ lat: 52.52, lng: 13.405 }),
      getBounds: () => bounds(52.5, 52.54),
    },
    state: {
      title: "Berlin",
      themeKey: null,
      opacity: 100,
      width: 100,
      data: { guardCoords: [[13.41, 52.52]], range: {} },
    },
  }
  const unbind = []
  const gallery = bindGalleryControls({
    find: (name) => nodes[name],
    on: (target, type, handler) => {
      target.addEventListener(type, handler)
      unbind.push(() => target.removeEventListener(type, handler))
    },
    studio,
    poster: { trackSource: "tracks" },
    pushEvent: (event, payload, reply) =>
      pushes.push({ event, payload, reply }),
    strings,
    setStatus: (text) => statuses.push(text),
  })
  gallery.refresh()
  assert.equal(save.disabled, false)
  assert.equal(notice.classList.contains("hidden"), true)
  save.dispatchEvent(new Event("click"))
  save.dispatchEvent(new Event("click"))
  assert.equal(pushes.length, 1)
  assert.equal(pushes[0].event, "poster:save")
  assert.equal(pushes[0].payload.name, "Berlin")
  assert.equal(pushes[0].payload.theme, "blueprint")
  assert.equal(pushes[0].payload.source, "tracks")
  assert.equal(save.disabled, true)
  assert.deepEqual(statuses, ["Queued"])
  pushes[0].reply({ status: "failed" })
  assert.equal(save.disabled, false)
  assert.deepEqual(statuses, ["Queued", ""])
  studio.state = { ...studio.state, data: { guardCoords: [] } }
  gallery.refresh()
  assert.equal(save.disabled, true)
  assert.equal(notice.textContent, "No location data.")
  assert.equal(notice.classList.contains("hidden"), false)
  for (const remove of unbind) remove()
})
