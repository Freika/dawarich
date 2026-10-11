import assert from "node:assert/strict"
import { test } from "node:test"
import { bindPosterControls } from "../../app-phoenix/assets/js/poster/controls.js"
import {
  dateRangeLabel,
  presetRange,
  toLocalDateTimeInput,
} from "../../app-phoenix/assets/js/poster/dates.js"
import { createPosterLifecycle } from "../../app-phoenix/assets/js/poster/lifecycle.js"
import { createPosterSource } from "../../app-phoenix/assets/js/poster/source.js"
import { bindStudioSwitch } from "../../app-phoenix/assets/js/poster/switch.js"

process.env.TZ = "Europe/Berlin"

const deferred = () => {
  let resolve
  const promise = new Promise((res) => {
    resolve = res
  })
  return { promise, resolve }
}

const tokens = {
  bg: "#101010",
  text: "#fafafa",
  water: "#0000ff",
  parks: "#00ff00",
  road_motorway: "#111111",
  road_primary: "#222222",
  road_secondary: "#333333",
  road_tertiary: "#444444",
  road_residential: "#555555",
  road_default: "#666666",
  route: "#ff0000",
}

function element(props = {}) {
  const target = new EventTarget()
  const classes = new Set(props.classes ?? [])
  return Object.assign(target, {
    dataset: {},
    value: "",
    checked: false,
    disabled: false,
    textContent: "",
    style: {},
    classList: {
      toggle: (name, on) => (on ? classes.add(name) : classes.delete(name)),
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
      contains: (name) => classes.has(name),
    },
    change(value) {
      if (typeof value === "boolean") this.checked = value
      else this.value = value
      this.dispatchEvent(new Event(this.inputEvent ?? "change"))
    },
    ...props,
  })
}

function controlsRoot() {
  const pdf = element({ value: "pdf" })
  const nodes = {
    layout: element({ value: "print-a3" }),
    "layout-dims": element(),
    summary: element(),
    format: element({ value: "png", querySelector: () => pdf }),
    "dpi-field": element(),
    dpi: element({ value: "300" }),
    "text-toggle": element({ checked: true }),
    title: element({ inputEvent: "input" }),
    subtitle: element({ inputEvent: "input" }),
    coords: element({ checked: true }),
    font: element({ value: "oswald" }),
    opacity: element({ value: "100", inputEvent: "input" }),
    "opacity-label": element(),
    width: element({ value: "100", inputEvent: "input" }),
    "width-label": element(),
    "date-start": element(),
    "date-end": element(),
    load: element(),
    "load-spinner": element({ classes: ["hidden"] }),
    "load-label": element(),
    "switch-video": element(),
    status: element(),
  }
  const labels = {
    "print-a3": "A3 Portrait",
    "social-story": "Story (9:16)",
    "print-a0": "A0 Portrait",
  }
  Object.defineProperty(nodes.layout, "selectedOptions", {
    get: () => [
      { textContent: `\n        ${labels[nodes.layout.value]}\n      ` },
    ],
  })
  const layers = [
    "roads",
    "water",
    "landuse",
    "buildings",
    "rail",
    "boundaries",
  ].map((key) =>
    element({
      dataset: { posterLayer: key },
      checked: ["roads", "water", "landuse"].includes(key),
    }),
  )
  const token = element({
    dataset: { posterToken: "route" },
    inputEvent: "input",
  })
  const tokenValue = element({ dataset: { posterTokenValue: "route" } })
  const presets = ["today", "week", "month"].map((range) =>
    element({ dataset: { posterRange: range } }),
  )
  return {
    nodes,
    pdf,
    layers,
    token,
    presets,
    querySelector: (selector) =>
      nodes[/^\[data-poster-([a-z-]+)\]$/.exec(selector)?.[1]] ?? null,
    querySelectorAll: (selector) =>
      ({
        "[data-poster-layer]": layers,
        "[data-poster-token]": [token],
        "[data-poster-token-value]": [tokenValue],
        "[data-poster-range]": presets,
      })[selector] ?? [],
  }
}

function lifecycle(poster) {
  const dialog = new EventTarget()
  dialog.showModal = () => {
    dialog.open = true
  }
  dialog.close = () => {
    dialog.open = false
  }
  const frame = { style: {}, clientWidth: 300, clientHeight: 400 }
  class FakeMap {
    constructor(options) {
      this.options = options
      this.touchZoomRotate = { disableRotation() {} }
      this.keyboard = { disableRotation() {} }
    }
    on() {}
    once() {}
    resize() {}
    remove() {}
    setStyle(style) {
      this.style = style
    }
    fitBounds(bounds) {
      this.fitted = bounds
    }
    getCenter() {
      return { lat: 1, lng: 2 }
    }
  }
  const studio = createPosterLifecycle({
    elements: {
      dialog,
      frame,
      stage: { clientWidth: 1000, clientHeight: 1000, children: [] },
      map: {},
      overlay: null,
      backdrop: null,
    },
    poster,
    loadLibrary: async () => ({ Map: FakeMap }),
    loadThemeTokens: async () => tokens,
    loadFonts: async () => {},
    label: (data) => dateRangeLabel(data.range, data.timeZone),
    window: {
      addEventListener() {},
      removeEventListener() {},
      getComputedStyle: () => ({
        paddingLeft: "0",
        paddingRight: "0",
        paddingTop: "0",
        paddingBottom: "0",
      }),
    },
    URL: { createObjectURL() {}, revokeObjectURL() {} },
  })
  return { studio, frame }
}

const range = (startAt, endAt) => ({
  startAt,
  endAt,
  importId: null,
  timezone: "America/Los_Angeles",
})

function mapPoster(applyDates = async () => ({})) {
  return {
    fixed: false,
    load: async () => ({
      geojson: { features: [] },
      guardCoords: [],
      defaultTitle: "",
      range: range("2020-04-17T07:00:00Z", "2020-04-18T06:59:00Z"),
      timeZone: "America/Los_Angeles",
    }),
    applyDates,
    fallbackBounds: () => null,
  }
}

test("layout change preserves WYSIWYG frame at effective DPI", async () => {
  const root = controlsRoot()
  const { studio, frame } = lifecycle(mapPoster())
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({ root, studio, maxDimensionPx: 8192 })
  assert.match(root.nodes.summary.textContent, /^A3 Portrait — 29\.7 × 42 cm/)
  assert.match(
    root.nodes.summary.textContent,
    /Export: 3508 × 4961px @ 300 dpi$/,
  )

  root.nodes.format.value = "pdf"
  root.nodes.layout.change("social-story")
  assert.equal(studio.state.layoutId, "social-story")
  const ratio =
    Number.parseFloat(frame.style.width) / Number.parseFloat(frame.style.height)
  assert.ok(Math.abs(ratio - 1080 / 1920) < 0.01, `ratio ${ratio}`)
  assert.equal(root.nodes["layout-dims"].textContent, "1080 × 1920 px")
  assert.equal(root.pdf.disabled, true)
  assert.equal(root.nodes.format.value, "png")
  assert.equal(root.nodes["dpi-field"].classList.contains("invisible"), true)
  assert.match(root.nodes.summary.textContent, /Export: 1080 × 1920px$/)

  root.nodes.layout.change("print-a0")
  assert.equal(root.pdf.disabled, false)
  assert.equal(root.nodes["dpi-field"].classList.contains("invisible"), false)
  assert.match(
    root.nodes.summary.textContent,
    /Export: 5794 × 8192px @ 175 dpi$/,
  )
  root.nodes.dpi.change("150")
  assert.equal(studio.state.dpi, 150)
  assert.match(root.nodes.summary.textContent, /@ 150 dpi$/)
  unbind()
  studio.close()
})

test("profile-date subtitle does not use browser timezone", async () => {
  assert.equal(
    dateRangeLabel(
      { startAt: "2020-04-17T00:00-07:00", endAt: "2020-04-17T23:59-07:00" },
      "America/Los_Angeles",
    ),
    "17 Apr 2020 – 17 Apr 2020",
  )
  assert.equal(
    toLocalDateTimeInput("2020-04-17T07:00:00Z", "America/Los_Angeles"),
    "2020-04-17T00:00",
  )
  assert.deepEqual(
    presetRange(
      "today",
      new Date("2020-04-18T05:00:00Z"),
      "America/Los_Angeles",
    ),
    { start: "2020-04-17T00:00", end: "2020-04-17T22:00" },
  )
  const root = controlsRoot()
  const { studio } = lifecycle(mapPoster())
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({ root, studio, maxDimensionPx: 8192 })
  assert.equal(root.nodes["date-start"].value, "2020-04-17T00:00")
  assert.equal(root.nodes["date-end"].value, "2020-04-17T23:59")
  assert.equal(root.nodes.subtitle.value, "17 Apr 2020 – 17 Apr 2020")
  unbind()
  studio.close()
})

test("switch to video is disabled during poster reload", async () => {
  const pending = deferred()
  const requested = []
  const poster = mapPoster(async (value) => {
    requested.push(value)
    await pending.promise
    return {
      geojson: { features: [] },
      guardCoords: [],
      defaultTitle: "",
      range: range("2020-04-10T07:00:00Z", "2020-04-11T06:59:00Z"),
      timeZone: "America/Los_Angeles",
    }
  })
  const root = controlsRoot()
  const { studio } = lifecycle(poster)
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({
    root,
    studio,
    poster,
    maxDimensionPx: 8192,
    strings: {
      load: "Load",
      loading: "Loading…",
      loading_tracks: "Loading tracks",
    },
  })
  root.nodes["date-start"].value = "2020-04-10T00:00"
  root.nodes["date-end"].value = "2020-04-10T23:59"
  root.nodes.load.dispatchEvent(new Event("click"))
  await Promise.resolve()
  assert.equal(root.nodes["switch-video"].disabled, true)
  assert.equal(root.nodes.load.disabled, true)
  assert.equal(root.nodes["load-label"].textContent, "Loading…")
  assert.equal(root.nodes["load-spinner"].classList.contains("hidden"), false)
  assert.equal(root.nodes.status.textContent, "Loading tracks")
  assert.equal(studio.state.rangeLoading, true)
  assert.deepEqual(requested, [range("2020-04-10T00:00", "2020-04-10T23:59")])
  pending.resolve()
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(root.nodes["switch-video"].disabled, false)
  assert.equal(root.nodes.load.disabled, false)
  assert.equal(root.nodes["load-label"].textContent, "Load")
  assert.equal(root.nodes.status.textContent, "")
  assert.equal(studio.state.rangeLoading, false)
  assert.equal(root.nodes.subtitle.value, "10 Apr 2020 – 10 Apr 2020")
  unbind()
  studio.close()
})

test("closing during a range reload keeps dates and the video switch usable after reopen", async () => {
  const requested = []
  const poster = mapPoster((value, { signal }) => {
    requested.push(value)
    if (requested.length > 1)
      return Promise.resolve({
        geojson: { features: [] },
        guardCoords: [],
        defaultTitle: "",
        range: range("2020-04-10T07:00:00Z", "2020-04-11T06:59:00Z"),
        timeZone: "America/Los_Angeles",
      })
    return new Promise((_resolve, reject) =>
      signal.addEventListener("abort", () =>
        reject(new DOMException("aborted", "AbortError")),
      ),
    )
  })
  const root = controlsRoot()
  const { studio } = lifecycle(poster)
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({
    root,
    studio,
    poster,
    maxDimensionPx: 8192,
    strings: { range_failed: "Failed to load location data." },
  })
  const videos = []
  bindStudioSwitch({
    find: (name) => root.nodes[name],
    on: (target, type, handler) => target.addEventListener(type, handler),
    studio,
    source: poster,
    openVideo: (source) => videos.push(source),
    close: () => studio.close(),
  })
  root.nodes["date-start"].value = "2020-04-10T00:00"
  root.nodes["date-end"].value = "2020-04-10T23:59"
  root.nodes.load.dispatchEvent(new Event("click"))
  await Promise.resolve()
  assert.equal(studio.state.rangeLoading, true)
  studio.close()
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(root.nodes.status.textContent, "")

  await studio.open({ themeKey: "noir" })
  assert.equal(studio.state.rangeLoading, false)
  root.nodes.load.dispatchEvent(new Event("click"))
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(requested.length, 2)
  assert.equal(root.nodes["switch-video"].disabled, false)
  root.nodes["switch-video"].dispatchEvent(new Event("click"))
  assert.deepEqual(videos, [poster])
  unbind()
  studio.close()
})

test("remounting for a different source shows controls that match the new studio state", async () => {
  const root = controlsRoot()
  const first = lifecycle(mapPoster())
  await first.studio.open({ themeKey: "noir" })
  const unbindFirst = bindPosterControls({
    root,
    studio: first.studio,
    maxDimensionPx: 8192,
  })
  root.nodes.dpi.change("150")
  root.nodes.layout.change("social-story")
  root.nodes.font.change("inter")
  root.nodes.opacity.change("40")
  root.nodes.width.change("150")
  root.nodes.coords.change(false)
  root.layers[0].change(false)
  root.layers[3].change(true)
  root.nodes["text-toggle"].change(false)
  unbindFirst()
  first.studio.close()

  const second = lifecycle(mapPoster())
  await second.studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({
    root,
    studio: second.studio,
    maxDimensionPx: 8192,
  })
  const { state } = second.studio
  assert.equal(root.nodes.layout.value, state.layoutId)
  assert.equal(root.nodes.format.value, state.format)
  assert.equal(root.nodes.dpi.value, String(state.dpi))
  assert.equal(root.nodes.font.value, state.fontKey)
  assert.equal(root.nodes.opacity.value, String(state.opacity))
  assert.equal(root.nodes.width.value, String(state.width))
  assert.equal(root.nodes.coords.checked, state.coords)
  assert.equal(root.nodes["text-toggle"].checked, state.textEnabled)
  assert.equal(root.nodes.title.disabled, false)
  assert.equal(root.nodes.font.disabled, false)
  for (const layer of root.layers)
    assert.equal(
      layer.checked,
      !state.hidden.has(layer.dataset.posterLayer),
      layer.dataset.posterLayer,
    )
  assert.match(root.nodes.summary.textContent, /^A3 Portrait — /)
  assert.equal(root.nodes["opacity-label"].textContent, "100%")
  unbind()
  second.studio.close()
})

test("a failed range reload shows an error and restores the loaded dates", async () => {
  const poster = mapPoster(async () => {
    throw new Error("source acknowledgement timed out")
  })
  const root = controlsRoot()
  const { studio } = lifecycle(poster)
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({
    root,
    studio,
    poster,
    maxDimensionPx: 8192,
    strings: {
      load: "Load",
      loading: "Loading…",
      loading_tracks: "Loading tracks",
      range_failed: "Failed to load location data. Please try again.",
    },
  })
  assert.equal(root.nodes["date-start"].value, "2020-04-17T00:00")
  root.nodes["date-start"].value = "2020-04-10T00:00"
  root.nodes["date-end"].value = "2020-04-10T23:59"
  root.nodes.load.dispatchEvent(new Event("click"))
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.equal(
    root.nodes.status.textContent,
    "Failed to load location data. Please try again.",
  )
  assert.equal(root.nodes["date-start"].value, "2020-04-17T00:00")
  assert.equal(root.nodes["date-end"].value, "2020-04-17T23:59")
  assert.equal(root.nodes.load.disabled, false)
  assert.equal(root.nodes["switch-video"].disabled, false)
  assert.equal(studio.state.rangeLoading, false)
  unbind()
  studio.close()
})

test("a range reload whose source acknowledgement times out shows the error while the studio stays open", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] })
  const flush = async () => {
    for (let round = 0; round < 20; round++) await Promise.resolve()
  }
  const poster = createPosterSource({
    snapshot: async () => ({
      revision: 1,
      range: range("2020-04-17T07:00:00Z", "2020-04-18T06:59:00Z"),
      points: [],
      geojson: { type: "FeatureCollection", features: [] },
    }),
    applyDates: () => new Promise(() => {}),
  })
  const root = controlsRoot()
  const { studio } = lifecycle(poster)
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({
    root,
    studio,
    poster,
    maxDimensionPx: 8192,
    strings: { range_failed: "Failed to load location data." },
  })
  root.nodes["date-start"].value = "2020-04-10T00:00"
  root.nodes["date-end"].value = "2020-04-10T23:59"
  root.nodes.load.dispatchEvent(new Event("click"))
  await flush()
  assert.equal(studio.state.rangeLoading, true)
  t.mock.timers.tick(15000)
  await flush()
  assert.equal(root.nodes.status.textContent, "Failed to load location data.")
  assert.equal(root.nodes["date-start"].value, "2020-04-17T00:00")
  assert.equal(studio.state.rangeLoading, false)
  unbind()
  studio.close()
  poster.destroy()
})

test("text, font, layer and colour controls update hook-local studio state", async () => {
  const root = controlsRoot()
  const { studio } = lifecycle(mapPoster())
  await studio.open({ themeKey: "noir" })
  const unbind = bindPosterControls({ root, studio, maxDimensionPx: 8192 })
  assert.equal(root.nodes["opacity-label"].textContent, "100%")
  root.nodes.title.change("Berlin")
  root.nodes.font.change("inter")
  root.layers[0].change(false)
  root.nodes.opacity.change("40")
  root.nodes["text-toggle"].change(false)
  root.token.change("#00ff00")
  assert.equal(studio.state.title, "Berlin")
  assert.equal(studio.state.fontKey, "inter")
  assert.deepEqual([...studio.state.hidden].sort(), [
    "boundaries",
    "buildings",
    "rail",
    "roads",
  ])
  assert.equal(studio.state.opacity, 40)
  assert.equal(root.nodes["opacity-label"].textContent, "40%")
  assert.equal(studio.state.textEnabled, false)
  assert.equal(root.nodes.title.disabled, true)
  assert.equal(root.nodes.font.disabled, true)
  assert.equal(studio.tokens.route, "#00ff00")
  unbind()
  root.nodes.title.change("ignored")
  assert.equal(studio.state.title, "Berlin")
  studio.close()
})
