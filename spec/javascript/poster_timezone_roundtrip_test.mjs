// Read-only reproduction. Run with TZ=America/Los_Angeles node poster-timezone-repro.mjs.
// Real production call chain: Poster.seedDateInputs -> Poster.applyDates ->
// MapPageProvider.applyDates -> Map.handleTimelineDateNavigated ->
// Map.navigateTimelineDateRange -> DateManager.formatDateForAPI.
// Network/DOM/renderer adapters are in-memory; all date conversion stays real.
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// CI runs Node 18, which has no global CustomEvent.
globalThis.CustomEvent ??= class CustomEvent extends Event {
  constructor(type, options = {}) {
    super(type, options)
    this.detail = options.detail ?? null
  }
}

import { fileURLToPath } from "node:url"

process.env.TZ = "America/Los_Angeles"
const ROOT = fileURLToPath(new URL("../../", import.meta.url))
const read = (path) => readFile(`${ROOT}/${path}`, "utf8")
globalThis.__reviewBindings = []
let loaderId = 0
async function load(source, bindings = {}) {
  const id = loaderId++
  globalThis.__reviewBindings[id] = bindings
  const declarations = []
  const body = source.replace(
    /^import\s+([\s\S]*?)\s+from\s+"[^"]+"\n/gm,
    (_statement, clause) => {
      const names = []
      if (clause.includes("* as")) names.push(clause.split("* as")[1].trim())
      else {
        for (const part of (clause.match(/\{([\s\S]*)\}/)?.[1] || "").split(
          ",",
        )) {
          const name = part
            .trim()
            .split(/\s+as\s+/)
            .pop()
          if (name) names.push(name)
        }
        const defaultName = clause
          .replace(/\{[\s\S]*\}/, "")
          .replace(",", "")
          .trim()
        if (defaultName) names.push(defaultName)
      }
      for (const name of names) {
        if (name === "Controller") declarations.push("class Controller {}")
        else if (name === "ReplayHost") declarations.push("class ReplayHost {}")
        else
          declarations.push(
            `const ${name}=globalThis.__reviewBindings[${id}][${JSON.stringify(name)}] ?? (()=>{throw new Error('Unexpected dependency ${name} executed')})`,
          )
      }
      return ""
    },
  )
  return import(
    `data:text/javascript;base64,${Buffer.from(`${declarations.join("\n")}\n${body}\n// ${id}`).toString("base64")}`
  )
}
const i18n = await load(await read("app/javascript/i18n.js"))
const dateRange = await load(
  await read("app/javascript/video_studio/date_range.js"),
  i18n,
)
const { DateManager } = await load(
  await read("app/javascript/controllers/maps/maplibre/date_manager.js"),
)
const { anomaliesVisible } = await load(
  await read("app/javascript/maps_maplibre/utils/layer_dependencies.js"),
)
const basemap = await load(
  await read("app/javascript/maps_maplibre/utils/basemap_url.js"),
)
const { SettingsManager } = await load(
  await read("app/javascript/maps_maplibre/utils/settings_manager.js"),
  basemap,
)
const arcs = await load(
  await read("app/javascript/maps_maplibre/utils/flight_arcs.js"),
)
const { RouteSegmenter } = await load(
  await read("app/javascript/maps_maplibre/utils/route_segmenter.js"),
  arcs,
)
async function exercise(initial, zone) {
  const { MapDateRange } = await load(
    await read("app/javascript/controllers/maps/maplibre/date_range.js"),
    { DateManager, SettingsManager, anomaliesVisible },
  )
  const { default: MapController } = await load(
    await read("app/javascript/controllers/maps/maplibre_controller.js"),
    i18n,
  )
  const { MapPageProvider } = await load(
    await read("app/javascript/poster_studio/data/providers.js"),
    { RouteSegmenter },
  )
  const { default: Poster } = await load(
    await read("app/javascript/controllers/poster_studio_editor_controller.js"),
    { ...i18n, ...dateRange, MapPageProvider, trackBounds: () => null },
  )
  const map = Object.create(MapController.prototype)
  const network = []
  Object.assign(map, {
    startDateValue: initial.start,
    endDateValue: initial.end,
    timezoneValue: zone,
    layerManager: { getLayer: () => null },
    mapDataManager: { ensurePointsLoaded: async () => {} },
    api: {
      fetchTracks: async (params) => {
        network.push(params)
        return { type: "FeatureCollection", features: [] }
      },
    },
    loadMapData: async () => {
      network.push({ start_at: map.startDateValue, end_at: map.endDateValue })
    },
    timelineBridge: { clearDayHighlight() {} },
    refreshTimelineFeedIfActive() {},
    familyManager: { debouncedLoadHistory() {} },
  })
  map.dateRange = new MapDateRange(map)
  const navigationRequests = []
  const element = { id: "maps-maplibre-container" }
  globalThis.window = {
    location: { search: "" },
    history: {
      pushState(_state, _title, url) {
        window.location.search = url.slice(url.indexOf("?"))
      },
    },
  }
  globalThis.document = {
    documentElement: { lang: "en" },
    getElementById: (id) => (id === "maps-maplibre-container" ? element : null),
    querySelector: () => null,
    dispatchEvent(event) {
      if (event.type === "timeline-feed:date-navigated") {
        navigationRequests.push(event.detail)
        map.handleTimelineDateNavigated(event)
      }
      return true
    },
  }
  const application = { getControllerForElementAndIdentifier: () => map }
  const poster = Object.create(Poster.prototype)
  Object.assign(poster, {
    provider: new MapPageProvider({ application }),
    hasDateStartTarget: true,
    hasDateEndTarget: true,
    dateStartTarget: { value: "" },
    dateEndTarget: {
      value: "",
      setCustomValidity(value) {
        this.validationMessage = value
      },
      reportValidity() {},
    },
    subtitleInputTarget: { value: "custom subtitle" },
    statusTarget: { textContent: "" },
    hasLoadButtonTarget: false,
    hasSwitchButtonTarget: false,
    hasSaveButtonTarget: false,
    previewMap: null,
  })
  poster.seedDateInputs()
  const inputs = {
    start: poster.dateStartTarget.value,
    end: poster.dateEndTarget.value,
  }
  await poster.applyDates()
  return { inputs, map, navigationRequests, network, poster }
}

for (const [zone, start, end] of [
  ["Europe/Berlin", "2026-04-05T00:00:00+02:00", "2026-04-05T23:59:00+02:00"],
  ["Europe/Berlin", "2026-03-29T00:00:00+01:00", "2026-03-29T23:59:00+02:00"],
  ["Europe/Berlin", "2026-10-25T00:00:00+02:00", "2026-10-25T23:59:00+01:00"],
  [
    "America/New_York",
    "2026-11-01T00:00:00-04:00",
    "2026-11-01T23:59:00-05:00",
  ],
  [
    "Pacific/Auckland",
    "2026-01-01T00:00:00+13:00",
    "2026-01-01T23:59:00+13:00",
  ],
  ["Etc/UTC", "2026-04-05T00:00:00+00:00", "2026-04-05T23:59:00+00:00"],
]) {
  test(`Poster Load preserves both selected instants in ${zone} from a Los Angeles browser at ${start}`, async () => {
    const { map, navigationRequests, network } = await exercise(
      { start, end },
      zone,
    )
    assert.equal(navigationRequests.length, 1)
    assert.equal(network.length, 2)
    assert.equal(
      new Date(map.startDateValue).toISOString(),
      new Date(start).toISOString(),
    )
    assert.equal(
      new Date(map.endDateValue).toISOString(),
      new Date(end).toISOString(),
    )
  })
}
for (const start of ["2026-10-25T02:30:00+02:00"]) {
  test(`Poster rejects ambiguous owner wall time ${start} instead of silently choosing a browser instant`, async () => {
    // The autumn fold has two instants. The input cannot disambiguate it.
    const { poster, navigationRequests } = await exercise(
      { start, end: "2026-10-25T23:59:00+01:00" },
      "Europe/Berlin",
    )
    assert.equal(navigationRequests.length, 0)
    assert.ok(poster.dateEndTarget.validationMessage)
  })
}
