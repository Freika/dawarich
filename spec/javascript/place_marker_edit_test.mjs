import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/${path}`, import.meta.url), "utf8")

async function loadModule(path) {
  const body = (await read(`javascript/${path}`)).replace(
    /^import[\s\S]*?from "[^"]+"\n/gm,
    "",
  )
  const stubs = `
    class Controller {}
    class PointDragGesture { attach() {} detach() {} cancel() {} }
    const translate = (key) => key
    const Toast = { error() {}, success() {}, info() {} }
  `
  return import(
    `data:text/javascript;base64,${Buffer.from(stubs + body).toString("base64")}`
  )
}

const { EventHandlers } = await loadModule(
  "controllers/maps/maplibre/event_handlers.js",
)
const { default: MapsController } = await loadModule(
  "controllers/maps/maplibre_controller.js",
)
const { default: PlaceDetailController } = await loadModule(
  "controllers/place_detail_controller.js",
)
const { default: PlaceCreationController } = await loadModule(
  "controllers/place_creation_controller.js",
)
const { PlacesManager } = await loadModule(
  "controllers/maps/maplibre/places_manager.js",
)

const mapView = await read("views/map/maplibre/index.html.erb")
const drawerView = await read("views/places/_drawer.html.erb")

globalThis.document = Object.assign(new EventTarget(), {
  createElement: () => ({}),
})
globalThis.window = {
  location: { href: "http://localhost/map/v2" },
  history: {
    state: null,
    replaceState(_state, _title, url) {
      window.location.href = url.toString()
    },
  },
}

function wireMapActions(controllers) {
  const actions = mapView.match(/data-action="([^"]*place-detail[^"]*)"/)[1]
  for (const [, event, identifier, method] of actions.matchAll(
    /(\S+)@document->([\w-]+)#(\w+)/g,
  )) {
    const controller = controllers[identifier]
    if (controller)
      document.addEventListener(event, (e) => controller[method](e))
  }
}

function mountPlaceDetail() {
  const frame = {
    src: null,
    removeAttribute(name) {
      this[name] = null
    },
    replaceChildren() {},
  }
  const detail = new PlaceDetailController()
  detail.frameTarget = frame
  wireMapActions({ "place-detail": detail })
  return { detail, frame }
}

function placeFeature(id) {
  return {
    type: "Feature",
    properties: { id },
    geometry: { type: "Point", coordinates: [13.405, 52.52] },
  }
}

function mountPlaceEditor() {
  const override = []
  const checkboxes = [1, 2].map((id) =>
    Object.assign(new EventTarget(), { value: String(id), checked: false }),
  )
  const form = {
    action: "/places",
    querySelector: () => override[0] ?? null,
    querySelectorAll: () => checkboxes,
    prepend: (input) => override.unshift(input),
  }
  const editor = new PlaceCreationController()
  Object.assign(editor, {
    formTarget: form,
    nameInputTarget: { value: "", focus() {} },
    latitudeInputTarget: {},
    longitudeInputTarget: {},
    modalTarget: { classList: new Set() },
  })
  editor.connect()
  return { editor, form, checkboxes, override }
}

function drawerEditAction() {
  const button = [...drawerView.matchAll(/<button\b(?:<%[\s\S]*?%>|[^>])*>/g)]
    .map(([tag]) => tag)
    .find((tag) => tag.includes('data-entity-type="place"'))
  assert.ok(button, "the place drawer renders no place Edit button")
  return button.match(/data-action="maps--maplibre#(\w+)"/)[1]
}

test("a place marker click opens the drawer whose Edit loads the place's name and tags into the editor", async () => {
  const { frame } = mountPlaceDetail()
  const { editor, form, checkboxes, override } = mountPlaceEditor()
  const movements = []
  const handlers = new EventHandlers(
    {
      flyTo: (options) => movements.push(options),
      getZoom: () => 10,
    },
    {},
  )

  handlers.handlePlaceClick({
    features: [
      { properties: { id: 5 }, geometry: { coordinates: [13.405, 52.52] } },
    ],
  })

  assert.deepEqual(movements, [{ center: [13.405, 52.52], zoom: 13 }])
  assert.equal(frame.src, "/places/5")
  assert.equal(window.location.href, "http://localhost/map/v2?place_id=5")

  const requests = []
  globalThis.fetch = async (url, options) => {
    requests.push([url, options.headers.Authorization])
    return {
      ok: true,
      json: async () => ({
        id: 5,
        name: "Corner cafe",
        latitude: 52.52,
        longitude: 13.405,
        tags: [{ id: 2 }],
      }),
    }
  }
  const maps = new MapsController()
  maps.apiKeyValue = "test-api-key"
  const edited = new Promise((resolve) =>
    document.addEventListener("place:edit", resolve, { once: true }),
  )

  maps[drawerEditAction()]({
    currentTarget: { dataset: { id: "5", entityType: "place" } },
  })
  await edited

  assert.deepEqual(requests, [["/api/v1/places/5", "Bearer test-api-key"]])
  assert.equal(editor.editingPlaceId, 5)
  assert.equal(editor.nameInputTarget.value, "Corner cafe")
  assert.deepEqual(
    checkboxes.map((checkbox) => checkbox.checked),
    [false, true],
  )
  assert.equal(form.action, "/places/5")
  assert.equal(override[0].value, "patch")
  assert.ok(editor.modalTarget.classList.has("modal-open"))
})

test("deleting the place from the drawer closes it and removes its marker from the map", () => {
  const { detail, frame } = mountPlaceDetail()
  const places = {
    data: {
      type: "FeatureCollection",
      features: [placeFeature(5), placeFeature(6)],
    },
    update(data) {
      this.data = data
    },
  }
  const maps = new MapsController()
  maps.placesManager = new PlacesManager({
    layerManager: { getLayer: (name) => (name === "places" ? places : null) },
  })
  wireMapActions({ "maps--maplibre": maps })
  frame.src = "/places/5"
  window.location.href = "http://localhost/map/v2?place_id=5"

  detail.deleted({ detail: { success: false }, params: { id: 5 } })

  assert.equal(frame.src, "/places/5")
  assert.deepEqual(
    places.data.features.map((feature) => feature.properties.id),
    [5, 6],
  )

  detail.deleted({ detail: { success: true }, params: { id: 5 } })

  assert.equal(frame.src, null)
  assert.equal(window.location.href, "http://localhost/map/v2")
  assert.deepEqual(
    places.data.features.map((feature) => feature.properties.id),
    [6],
  )
})
