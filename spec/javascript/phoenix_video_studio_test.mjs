import assert from "node:assert/strict"
import test from "node:test"
import { VideoStudio } from "../../app-phoenix/assets/js/hooks/video_studio.js"
import { createStudioSource } from "../../app-phoenix/assets/js/map/data/studio_source.js"
import { mountVideoStudio } from "../../app-phoenix/assets/js/video/studio.js"

const deferred = () => {
  let resolve
  let reject
  const promise = new Promise((done, fail) => {
    resolve = done
    reject = fail
  })
  return { promise, resolve, reject }
}
const tick = () => new Promise((resolve) => setImmediate(resolve))
const settle = async () => {
  for (let i = 0; i < 8; i += 1) await tick()
}

function context2d() {
  const target = {
    measureText: (value) => ({ width: String(value).length * 6 }),
    createLinearGradient: () => ({ addColorStop() {} }),
  }
  return new Proxy(target, {
    get: (object, key) => (key in object ? object[key] : () => {}),
    set: (object, key, value) => {
      object[key] = value
      return true
    },
  })
}

function element(dataset = {}, extra = {}) {
  const listeners = {}
  const classes = new Set(extra.classes ?? [])
  const el = {
    dataset: { ...dataset },
    value: extra.value ?? "",
    type: extra.type ?? "text",
    textContent: "",
    disabled: false,
    checked: false,
    style: {},
    attributes: {},
    classes,
    listeners,
    open: false,
    classList: {
      toggle(name, on = !classes.has(name)) {
        if (on) classes.add(name)
        else classes.delete(name)
      },
      add: (...names) => {
        for (const name of names) classes.add(name)
      },
      remove: (...names) => {
        for (const name of names) classes.delete(name)
      },
      contains: (name) => classes.has(name),
    },
    setAttribute(key, value) {
      el.attributes[key] = String(value)
    },
    getAttribute: (key) => el.attributes[key] ?? null,
    removeAttribute(key) {
      delete el.attributes[key]
    },
    addEventListener(type, fn) {
      if (!listeners[type]) listeners[type] = new Set()
      listeners[type].add(fn)
    },
    removeEventListener(type, fn) {
      listeners[type]?.delete(fn)
    },
    emit(type, detail = {}) {
      for (const fn of [...(listeners[type] ?? [])])
        fn({
          type,
          target: el,
          currentTarget: el,
          preventDefault() {},
          ...detail,
        })
    },
    getBoundingClientRect: () => ({ width: 360, height: 640 }),
    getContext: () => context2d(),
    setCustomValidity(message) {
      el.validity = message
    },
    reportValidity() {},
    showModal() {
      el.open = true
    },
    close() {
      el.open = false
    },
    replaceChildren(...children) {
      el.children = children
    },
    load() {},
  }
  return el
}

function studioRoot() {
  const single = {}
  for (const name of [
    "dialog",
    "stage",
    "frame",
    "preview",
    "overlay",
    "result",
    "status",
    "progress",
    "render",
    "cancel",
    "save",
    "close",
    "switch",
    "load",
    "load-spinner",
    "name",
    "start",
    "end",
    "range-controls",
    "range-display",
    "range-label",
    "summary",
    "theme-label",
    "format-dims",
    "fog-controls",
  ])
    single[name] = element()
  const lists = {
    theme: ["terracotta", "noir"].map((key) =>
      element({ key, name: key === "noir" ? "Noir" : "Terracotta" }),
    ),
    format: ["portrait", "square"].map((format) =>
      element({
        format,
        label: format === "square" ? "Quadrat" : "Hochformat",
      }),
    ),
    mode: ["route", "fog"].map((mode) => element({ mode })),
    setting: [
      element({ videoSetting: "duration_sec" }, { type: "range", value: "15" }),
      element({ videoSetting: "show_marker" }, { type: "checkbox" }),
    ],
    reset: [element({ videoReset: "track_color" })],
    label: [element({ videoLabel: "duration_sec" })],
  }
  const dispatched = []
  const root = {
    dataset: {
      videoConfig: JSON.stringify({
        fonts: { "inter-400": "/fonts/inter.woff2" },
        strings: {
          open_failed: "Öffnen fehlgeschlagen: %{error}",
          save_failed: "Speichern fehlgeschlagen: %{error}",
          empty_track: "Keine Route",
          ready: "Fertig — %{size} MB",
          rendering: "Rendern… %{percent}%",
          uploading: "Hochladen… %{percent}%",
          unsupported_browser: "Browser kann nicht kodieren",
          start_before_end: "Start vor Ende",
          loading_tracks: "Lade…",
          summary: "%{format} — %{width} × %{height} · %{theme} · %{seconds}s",
          "stats.distance": "Distanz",
          "stats.duration": "Dauer",
          "stats.avg_speed": "Tempo",
          "hud.day": "TAG",
          "hud.distance": "DISTANZ",
          "hud.of_total": "GESAMT",
          "hud.tagline": "PRIVAT",
          "hud.travelled_over": "über %{days} Tage",
        },
      }),
    },
    single,
    lists,
    dispatched,
    querySelector: (selector) =>
      single[/^\[data-video-([\w-]+)\]$/.exec(selector)?.[1]] ?? null,
    querySelectorAll: (selector) =>
      lists[/^\[data-video-([\w-]+)\]$/.exec(selector)?.[1]] ?? [],
    dispatchEvent: (event) => dispatched.push(event),
  }
  return root
}

const POINTS = [
  { longitude: "12.3712", latitude: "51.3402", timestamp: 1_787_212_800 },
  { longitude: "12.3760", latitude: "51.3402", timestamp: 1_787_213_400 },
  { longitude: "12.3800", latitude: "51.3410", timestamp: 1_787_214_000 },
]
const TRACK = {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      properties: {},
      geometry: {
        type: "LineString",
        coordinates: POINTS.map((point) => [
          Number(point.longitude),
          Number(point.latitude),
        ]),
      },
    },
  ],
}

function harness({
  track,
  fonts,
  theme,
  fixedRange = false,
  rangeChange,
  ignoreAbort = false,
} = {}) {
  const maps = []
  class FakeMap {
    constructor(options) {
      this.options = options
      this.removed = false
      this.styles = []
      maps.push(this)
    }
    once() {}
    off() {}
    setStyle(style) {
      this.styles.push(style)
    }
    resize() {}
    fitBounds() {}
    project([x, y]) {
      return { x, y }
    }
    getCanvas() {
      return { clientWidth: 360, clientHeight: 640 }
    }
    remove() {
      this.removed = true
    }
  }
  let state = {
    revision: 1,
    title: "",
    range: {
      startAt: "2026-08-20T00:00:00+02:00",
      endAt: "2026-08-20T23:59:00+02:00",
      timezone: "Europe/Berlin",
    },
  }
  const source = createStudioSource({
    getState: () => state,
    readSnapshot: async () =>
      track ? track.promise : { points: POINTS, geojson: TRACK },
    applyDates:
      rangeChange ??
      (async (range) => {
        state = {
          ...state,
          revision: state.revision + 1,
          range: { ...state.range, ...range },
        }
        return { revision: state.revision }
      }),
    fixedRange,
  })
  const revoked = []
  const created = []
  const renders = []
  const uploads = []
  const kit = {
    TRACK_SOURCE_ID: "poster-track",
    trackBounds: () => [
      [12.37, 51.34],
      [12.38, 51.342],
    ],
    loadThemeTokens: async (key) =>
      theme
        ? theme.promise
        : { bg: "#ffffff", name: key === "noir" ? "Noir" : "Terracotta" },
    resolveTheme: (tokens) => tokens,
    buildPosterStyle: (options) => ({ version: 8, options }),
  }
  const deps = {
    loadLibrary: async () => ({ Map: FakeMap }),
    loadKit: async () => kit,
    ensureFonts: async (_urls, { signal } = {}) => {
      if (fonts) await fonts.promise
      if (signal?.aborted) throw new DOMException("closed", "AbortError")
      return { mono: "Mono", sans: "Sans" }
    },
    renderVideo: (options) => {
      const run = deferred()
      renders.push({ options, run })
      if (!ignoreAbort)
        options.signal.addEventListener("abort", () =>
          run.reject(new DOMException("Render cancelled", "AbortError")),
        )
      return run.promise
    },
    upload: (options) => {
      const run = deferred()
      uploads.push({ options, run })
      options.signal.addEventListener("abort", () =>
        run.reject(new DOMException("Upload cancelled", "AbortError")),
      )
      return run.promise
    },
    URL: {
      createObjectURL: (blob) => {
        created.push(blob)
        return `blob:${created.length}`
      },
      revokeObjectURL: (url) => revoked.push(url),
    },
    window: {
      devicePixelRatio: 1,
      addEventListener() {},
      removeEventListener() {},
    },
    isSupported: () => true,
  }
  const root = studioRoot()
  const studio = mountVideoStudio({
    root,
    source,
    request: async () => ({ ok: true }),
    deps,
  })
  return { root, studio, maps, revoked, created, renders, uploads, source }
}

test("an opened studio previews the snapshot route with one map", async () => {
  const h = harness()
  await h.studio.open()
  assert.equal(h.root.single.dialog.open, true)
  assert.equal(h.maps.length, 1)
  assert.equal(h.maps[0].options.container, h.root.single.preview)
  assert.equal(h.root.single.render.disabled, false)
  assert.match(h.root.single.name.value, /2026/)
  assert.equal(h.root.single["range-controls"].classes.has("hidden"), false)
  assert.equal(h.root.single.start.value, "2026-08-20T00:00")
  h.studio.destroy()
  assert.equal(h.maps[0].removed, true)
})

test("close during font style or track load creates no preview map", async () => {
  for (const stage of ["track", "fonts", "theme"]) {
    const gate = deferred()
    const h = harness({ [stage]: gate })
    const opening = h.studio.open()
    await settle()
    h.studio.close()
    gate.resolve(
      stage === "track"
        ? { points: POINTS, geojson: TRACK }
        : stage === "theme"
          ? { bg: "#fff", name: "Terracotta" }
          : undefined,
    )
    await opening
    await settle()
    assert.equal(h.maps.length, 0, stage)
    assert.equal(h.root.single.dialog.open, false, stage)
  }
})

test("an invalidated theme load cannot mutate a reopened studio", async () => {
  const gate = deferred()
  const h = harness({ theme: gate })
  const first = h.studio.open()
  await settle()
  h.studio.close()
  const second = h.studio.open()
  await settle()
  gate.resolve({ bg: "#000", name: "Noir" })
  await Promise.all([first, second])
  await settle()
  assert.equal(h.maps.length, 1)
})

test("destroy aborts render/upload and revokes result URL", async () => {
  const h = harness()
  await h.studio.open()
  const rendering = h.studio.render()
  await settle()
  h.renders[0].run.resolve({ blob: new Blob(["mp4"], { type: "video/mp4" }) })
  await rendering
  assert.equal(h.root.single.result.src, "blob:1")
  assert.equal(h.root.single.save.disabled, false)
  const saving = h.studio.save()
  await settle()
  const uploadSignal = h.uploads[0].options.signal
  assert.equal(h.uploads[0].options.settings.source, "map")
  const second = h.studio.render()
  await settle()
  const renderSignal = h.renders[1]?.options.signal
  h.studio.destroy()
  await Promise.allSettled([saving, second])
  assert.equal(uploadSignal.aborted, true)
  assert.equal(renderSignal === undefined || renderSignal.aborted, true)
  assert.ok(h.revoked.includes("blob:1"))
})

test("an old render result cannot replace a newer one", async () => {
  const h = harness({ ignoreAbort: true })
  await h.studio.open()
  const first = h.studio.render()
  await settle()
  const stale = h.renders[0]
  h.studio.cancel()
  stale.run.resolve({ blob: new Blob(["stale"]) })
  await first
  assert.equal(h.created.length, 0)
  const second = h.studio.render()
  await settle()
  h.renders[1].run.resolve({ blob: new Blob(["new"]) })
  await second
  assert.equal(h.created.length, 1)
  assert.equal(h.root.single.result.src, "blob:1")
})

test("switching studios retains current range with one map per owner", async () => {
  const h = harness()
  await h.studio.open()
  assert.equal(h.maps.length, 1)
  h.studio.switchStudio()
  assert.equal(h.maps[0].removed, true)
  assert.equal(h.root.single.dialog.open, false)
  const [event] = h.root.dispatched
  assert.equal(event.type, "dawarich:studio-switch")
  assert.equal(event.detail.studio, "poster")
  assert.equal(event.detail.source, h.source)
  const snapshot = await h.source.snapshot({ purpose: "poster" })
  assert.equal(snapshot.range.startAt, "2026-08-20T00:00:00+02:00")
})

test("studio cannot switch to poster while a range is loading", async () => {
  const gate = deferred()
  const h = harness({ rangeChange: () => gate.promise })
  await h.studio.open()
  h.root.single.start.value = "2026-08-21T08:00"
  h.root.single.end.value = "2026-08-21T18:00"
  const loading = h.studio.applyDates()
  await settle()
  h.studio.switchStudio()
  assert.equal(h.root.dispatched.length, 0)
  assert.equal(h.root.single.switch.disabled, true)
  h.studio.close()
  gate.resolve({ revision: 99 })
  await loading.catch(() => null)
})

test("studio reloads from the exact date and time selected", async () => {
  const seen = []
  const h = harness({
    rangeChange: async (range) => {
      seen.push(range)
      return { revision: 1 }
    },
  })
  await h.studio.open()
  h.root.single.start.value = "2026-03-28T10:00"
  h.root.single.end.value = "2026-03-30T10:00"
  await h.studio.applyDates()
  assert.deepEqual(seen, [
    { startAt: "2026-03-28T10:00+01:00", endAt: "2026-03-30T10:00+02:00" },
  ])
})

test("studio rejects an end time that is not later than the start", async () => {
  const seen = []
  const h = harness({
    rangeChange: async (range) => {
      seen.push(range)
      return { revision: 1 }
    },
  })
  await h.studio.open()
  h.root.single.start.value = "2026-08-21T18:00"
  h.root.single.end.value = "2026-08-21T08:00"
  await h.studio.applyDates()
  assert.deepEqual(seen, [])
  assert.equal(h.root.single.end.validity, "Start vor Ende")
})

test("a trip studio shows a fixed range and keeps its trip title", async () => {
  const h = harness({ fixedRange: true })
  await h.studio.open()
  assert.equal(h.root.single["range-controls"].classes.has("hidden"), true)
  assert.equal(h.root.single["range-display"].classes.has("hidden"), false)
})

test("format buttons update the render format and its localized label", async () => {
  const h = harness()
  await h.studio.open()
  h.root.lists.format[1].emit("click")
  await settle()
  assert.equal(h.studio.settings.format, "square")
  assert.equal(
    h.root.single["format-dims"].textContent,
    "1080 × 1080 · 15s · 30 fps",
  )
  assert.equal(h.root.lists.format[1].attributes["aria-checked"], "true")
  assert.match(h.root.single.summary.children[0].textContent, /^Quadrat — 1080/)
})

test("an empty range refuses to render with the localized notice", async () => {
  const gate = deferred()
  const h = harness({ track: gate })
  const opening = h.studio.open()
  await settle()
  gate.resolve({ points: POINTS.slice(0, 1), geojson: TRACK })
  await opening
  await h.studio.render()
  assert.equal(h.renders.length, 0)
  assert.equal(h.root.single.status.textContent, "Keine Route")
})

test("the hook mounts one owner per element across reconnects", async () => {
  const runtimes = []
  const hook = Object.create(VideoStudio)
  const root = studioRoot()
  Object.assign(hook, {
    el: root,
    loader: async () => ({
      mountVideoStudio: (options) => {
        const owner = {
          options,
          opened: 0,
          destroyed: false,
          open() {
            this.opened += 1
          },
          destroy() {
            this.destroyed = true
          },
        }
        runtimes.push(owner)
        return owner
      },
    }),
    pushEventTo: () => {},
  })
  const listeners = {}
  root.addEventListener = (type, fn) => {
    listeners[type] = fn
  }
  root.removeEventListener = (type, fn) => {
    if (listeners[type] === fn) delete listeners[type]
  }
  hook.mounted()
  const source = { snapshot() {} }
  await listeners["dawarich:video-studio-open"]({ detail: { source } })
  hook.reconnected?.()
  await listeners["dawarich:video-studio-open"]({ detail: { source } })
  assert.equal(runtimes.length, 1)
  assert.equal(runtimes[0].opened, 2)
  assert.equal(runtimes[0].options.source, source)
  hook.destroyed()
  assert.equal(runtimes[0].destroyed, true)
  assert.equal(listeners["dawarich:video-studio-open"], undefined)
})
