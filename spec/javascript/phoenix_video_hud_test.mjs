import assert from "node:assert/strict"
import test from "node:test"
import {
  ensureHudFonts,
  HUD_MONO_FAMILY,
  HUD_SANS_FAMILY,
} from "../../app-phoenix/assets/js/video/hud_fonts.js"
import {
  dayNumber,
  dayTotal,
  formatDateRange,
  splitDistance,
} from "../../app-phoenix/assets/js/video/hud_format.js"
import { drawHud } from "../../app-phoenix/assets/js/video/hud_overlay.js"
import {
  drawFogOverlay,
  drawRouteMarker,
} from "../../app-phoenix/assets/js/video/map_effects.js"
import {
  MAX_HUD_SCALE,
  MIN_HUD_SCALE,
} from "../../app-phoenix/assets/js/video/state.js"

function recordingContext() {
  const drawn = []
  const stops = []
  const fonts = []
  const noop = () => {}
  let currentFont = "10px mono"
  const fontPx = () => Number(/(\d+(?:\.\d+)?)px/.exec(currentFont)?.[1]) || 10
  const ctx = {
    drawn,
    fonts,
    canvas: { width: 1080, height: 1920 },
    fillText: (text) => drawn.push(text),
    measureText: (t) => ({ width: String(t).length * fontPx() * 0.6 }),
    stops,
    createLinearGradient: () => ({
      addColorStop: (_offset, color) => stops.push(color),
    }),
    save: noop,
    restore: noop,
    beginPath: noop,
    closePath: noop,
    moveTo: noop,
    arc: noop,
    arcTo: noop,
    fill: noop,
    fillRect: noop,
  }
  Object.defineProperty(ctx, "font", {
    configurable: true,
    get: () => currentFont,
    set: (v) => {
      currentFont = v
      ctx.fonts.push(v)
    },
  })
  return ctx
}

const LABELS = {
  day: "TAG",
  distance: "DISTANZ",
  ofTotal: "GESAMT",
  tagline: "PRIVATE STANDORTHISTORIE",
  travelledOver: (days) => `unterwegs an ${days} Tagen`,
}

const CLOCK = {
  startTs: Date.parse("2026-06-14T08:00:00Z"),
  endTs: Date.parse("2026-06-16T18:00:00Z"),
  entries: [
    { dist: 0, ts: Date.parse("2026-06-14T08:00:00Z") },
    { dist: 10000, ts: Date.parse("2026-06-16T18:00:00Z") },
  ],
  totalDistance: 10000,
}

function draw(overrides = {}) {
  const ctx = recordingContext()
  drawHud(ctx, {
    width: 1080,
    height: 1920,
    fraction: 0.5,
    outroProgress: 0,
    distanceM: 5000,
    stats: { distanceM: 10000 },
    units: "km",
    accent: "#2563EB",
    clock: CLOCK,
    labels: LABELS,
    watermark: "dawarich.example",
    families: { mono: "Mono", sans: "Sans" },
    ...overrides,
  })
  return ctx.drawn
}

test("the replay chrome draws the supplied labels, not hardcoded English", () => {
  const drawn = draw()

  assert.ok(drawn.some((text) => text.startsWith("TAG ")))
  assert.ok(drawn.includes("DISTANZ"))
  assert.ok(drawn.includes("GESAMT"))
  assert.ok(!drawn.includes("DISTANCE"))
})

test("the summary frame draws the supplied labels", () => {
  const drawn = draw({ outroProgress: 1 })

  assert.ok(drawn.includes("PRIVATE STANDORTHISTORIE"))
  assert.ok(drawn.some((text) => /^unterwegs an \d+ Tagen$/.test(text)))
})

test("the watermark appears on both the chrome and the summary", () => {
  assert.ok(draw().includes("dawarich.example"))
  assert.ok(draw({ outroProgress: 1 }).includes("dawarich.example"))
})

test("no watermark is drawn when it is switched off", () => {
  assert.ok(!draw({ watermark: null }).includes("dawarich.example"))
  assert.ok(
    !draw({ watermark: null, outroProgress: 1 }).includes("dawarich.example"),
  )
})

test("switching the watermark off keeps the rest of the HUD intact", () => {
  const drawn = draw({ watermark: null })

  assert.ok(drawn.includes("DISTANZ"))
  assert.ok(drawn.length > 0)
})

test("a file with no timestamps still renders a distance-only HUD", () => {
  const drawn = draw({ clock: null })

  assert.ok(drawn.includes("DISTANZ"))
  assert.ok(!drawn.some((text) => text.startsWith("TAG ")))
})

test("the font families reach the canvas", () => {
  const ctx = recordingContext()
  drawHud(ctx, {
    width: 1080,
    height: 1920,
    fraction: 0.5,
    outroProgress: 0,
    distanceM: 5000,
    stats: { distanceM: 10000 },
    units: "km",
    accent: "#2563EB",
    clock: CLOCK,
    labels: LABELS,
    watermark: null,
    families: { mono: "Video HUD Mono", sans: "Video HUD Sans" },
  })

  assert.ok(ctx.fonts.some((font) => font.includes('"Video HUD Mono"')))
})

function scrimAlphas(themeBg, outroProgress = 0) {
  const ctx = recordingContext()
  drawHud(ctx, {
    width: 1080,
    height: 1920,
    fraction: 0.5,
    outroProgress,
    distanceM: 5000,
    stats: { distanceM: 10000 },
    units: "km",
    accent: "#2563EB",
    clock: CLOCK,
    labels: LABELS,
    watermark: null,
    families: { mono: "Mono", sans: "Sans" },
    themeBg,
  })
  return ctx.stops
    .map((color) => Number(/rgba\(6, 6, 8, ([0-9.]+)\)/.exec(color)?.[1]))
    .filter((alpha) => Number.isFinite(alpha))
}

test("a near-black map gets far less scrim than a white one", () => {
  const dark = Math.max(...scrimAlphas("#000000"))
  const light = Math.max(...scrimAlphas("#ffffff"))

  assert.ok(dark < light * 0.35, `expected ${dark} well below ${light}`)
})

test("the summary frame stops short of an opaque black wash on a dark map", () => {
  const dark = Math.max(...scrimAlphas("#000000", 1))

  assert.ok(dark < 0.4, `summary scrim was ${dark}`)
})

test("a pale map keeps the full wash so white text stays legible", () => {
  const light = Math.max(...scrimAlphas("#ffffff", 1))

  assert.ok(light > 0.9, `summary scrim was ${light}`)
})

test("scrim weight tracks luminance, not just light-vs-dark", () => {
  const black = Math.max(...scrimAlphas("#000000"))
  const mid = Math.max(...scrimAlphas("#808080"))
  const white = Math.max(...scrimAlphas("#ffffff"))

  assert.ok(black < mid && mid < white)
})

test("a missing theme background falls back to the full wash", () => {
  const missing = Math.max(...scrimAlphas(undefined))
  const white = Math.max(...scrimAlphas("#ffffff"))

  assert.equal(missing, white)
})

function fontSizes(width, height, hudScale) {
  const ctx = recordingContext()
  for (const outroProgress of [0, 1]) {
    drawHud(ctx, {
      width,
      height,
      fraction: 0.5,
      outroProgress,
      distanceM: 5000,
      stats: { distanceM: 10000 },
      units: "km",
      accent: "#2563EB",
      clock: CLOCK,
      labels: LABELS,
      watermark: "dawarich.example",
      families: { mono: "Mono", sans: "Sans" },
      themeBg: "#ffffff",
      hudScale,
    })
  }
  return ctx.fonts
    .map((f) => Number(/(\d+(?:\.\d+)?)px/.exec(f)?.[1]))
    .filter((px) => Number.isFinite(px))
}

test("no HUD text falls below 2.2% of the frame's short edge", () => {
  const sizes = fontSizes(1080, 1920)
  const floor = 1080 * 0.022

  assert.ok(
    Math.min(...sizes) >= floor,
    `smallest was ${Math.min(...sizes).toFixed(1)}px, floor is ${floor.toFixed(1)}px`,
  )
})

test("the size floor holds in every export format", () => {
  for (const [w, h] of [
    [1080, 1920],
    [1920, 1080],
    [1080, 1080],
  ]) {
    const sizes = fontSizes(w, h)
    const floor = Math.min(w, h) * 0.022
    assert.ok(
      Math.min(...sizes) >= floor,
      `${w}x${h}: smallest ${Math.min(...sizes).toFixed(1)}px < ${floor.toFixed(1)}px`,
    )
  }
})

test("the headline figure still dominates the supporting text", () => {
  const sizes = fontSizes(1080, 1920).sort((a, b) => a - b)

  assert.ok(Math.max(...sizes) > Math.min(...sizes) * 4)
})

test("overlay size scales every string proportionally", () => {
  const normal = fontSizes(1080, 1920, 1)
  const large = fontSizes(1080, 1920, 1.6)

  assert.equal(normal.length, large.length)
  for (let i = 0; i < normal.length; i += 1) {
    assert.ok(Math.abs(large[i] / normal[i] - 1.6) < 0.001)
  }
})

test("the smallest overlay size still clears the readability floor", () => {
  const sizes = fontSizes(1080, 1920, 0.8)
  const floor = 1080 * 0.017

  assert.ok(
    Math.min(...sizes) >= floor,
    `smallest was ${Math.min(...sizes).toFixed(1)}px at 80%`,
  )
})

test("an omitted overlay size behaves as 100%", () => {
  assert.deepEqual(fontSizes(1080, 1920), fontSizes(1080, 1920, 1))
})

function footerTexts(hudScale) {
  const ctx = recordingContext()
  drawHud(ctx, {
    width: 1080,
    height: 1920,
    fraction: 0.5,
    outroProgress: 0,
    distanceM: 5000,
    stats: { distanceM: 10000 },
    units: "km",
    accent: "#2563EB",
    clock: CLOCK,
    labels: LABELS,
    watermark: "https://dawarich.app",
    families: { mono: "Mono", sans: "Sans" },
    themeBg: "#ffffff",
    hudScale,
  })
  return ctx.drawn
}

test("the credit is drawn at every overlay size the control offers", () => {
  for (let scale = MIN_HUD_SCALE; scale <= MAX_HUD_SCALE; scale += 5) {
    assert.ok(
      footerTexts(scale / 100).some((text) => text === "https://dawarich.app"),
      `credit missing at ${scale}%`,
    )
  }
})

test("the credit survives even past the control's ceiling", () => {
  assert.ok(footerTexts(2).some((text) => text === "https://dawarich.app"))
})

test("the footer dates are never dropped either", () => {
  assert.ok(footerTexts(2).some((t) => /JUN/.test(t)))
})

test("the footer row shrinks only when it has to", () => {
  const atMax = footerFontPx(MAX_HUD_SCALE / 100)
  const unscaled = ((1080 / 100) * (MAX_HUD_SCALE / 100) * 2.4).toFixed(3)

  assert.equal(atMax.toFixed(3), unscaled)
})

function footerFontPx(hudScale) {
  const ctx = recordingContext()
  drawHud(ctx, {
    width: 1080,
    height: 1920,
    fraction: 0.5,
    outroProgress: 0,
    distanceM: 5000,
    stats: { distanceM: 10000 },
    units: "km",
    accent: "#2563EB",
    clock: CLOCK,
    labels: LABELS,
    watermark: "https://dawarich.app",
    families: { mono: "Mono", sans: "Sans" },
    themeBg: "#ffffff",
    hudScale,
  })
  const target = (1080 / 100) * hudScale * 2.4
  return ctx.fonts
    .map((f) => Number(/(\d+(?:\.\d+)?)px/.exec(f)?.[1]))
    .filter((px) => Number.isFinite(px) && px <= target + 0.001)
    .sort((a, b) => b - a)[0]
}

function effectsContext() {
  const calls = []
  const ctx = {
    calls,
    clearRect: (...args) => calls.push(["clearRect", ...args]),
    fillRect: (...args) => calls.push(["fillRect", ...args]),
    save: () => calls.push(["save"]),
    restore: () => calls.push(["restore"]),
    beginPath: () => calls.push(["beginPath"]),
    moveTo: (...args) => calls.push(["moveTo", ...args]),
    lineTo: (...args) => calls.push(["lineTo", ...args]),
    stroke: () => calls.push(["stroke"]),
    arc: (...args) => calls.push(["arc", ...args]),
    fill: () => calls.push(["fill"]),
  }
  for (const property of [
    "fillStyle",
    "strokeStyle",
    "lineWidth",
    "lineCap",
    "lineJoin",
    "globalCompositeOperation",
  ]) {
    Object.defineProperty(ctx, property, {
      set: (value) => calls.push([property, value]),
    })
  }
  return ctx
}

const map = {
  project: ([x, y]) => ({ x, y }),
  getCanvas: () => ({ clientWidth: 100, clientHeight: 200 }),
}

const route = [
  {
    type: "Feature",
    properties: {},
    geometry: {
      type: "LineString",
      coordinates: [
        [10, 20],
        [30, 40],
      ],
    },
  },
]

test("fog covers the frame and erases the travelled corridor", () => {
  const ctx = effectsContext()
  drawFogOverlay(ctx, {
    map,
    features: route,
    head: [30, 40],
    width: 200,
    height: 400,
    opacity: 0.7,
  })

  assert.ok(ctx.calls.some((call) => call[0] === "fillRect"))
  assert.ok(
    ctx.calls.some(
      (call) =>
        call[0] === "globalCompositeOperation" && call[1] === "destination-out",
    ),
  )
  assert.ok(ctx.calls.some((call) => call[0] === "moveTo" && call[1] === 20))
  assert.ok(ctx.calls.some((call) => call[0] === "lineTo" && call[1] === 60))
  assert.ok(ctx.calls.some((call) => call[0] === "arc" && call[1] === 60))
})

test("a transparent fog clears the old overlay without painting a new one", () => {
  const ctx = effectsContext()
  drawFogOverlay(ctx, { map, width: 200, height: 400, opacity: 0 })

  assert.deepEqual(ctx.calls, [["clearRect", 0, 0, 200, 400]])
})

test("fog uses the selected overlay color", () => {
  const ctx = effectsContext()
  drawFogOverlay(ctx, {
    map,
    width: 200,
    height: 400,
    opacity: 0.7,
    color: "#123456",
  })

  assert.ok(
    ctx.calls.some(
      (call) => call[0] === "fillStyle" && call[1] === "rgba(18, 52, 86, 0.7)",
    ),
  )
})

test("the route marker is scaled from map CSS pixels into the video", () => {
  const ctx = effectsContext()
  drawRouteMarker(ctx, {
    map,
    coordinate: [25, 50],
    width: 200,
    height: 400,
    accent: "#ff0000",
  })

  const arcs = ctx.calls.filter((call) => call[0] === "arc")
  assert.equal(arcs.length, 2)
  assert.deepEqual(arcs[0].slice(1, 3), [50, 100])
  assert.ok(
    ctx.calls.some((call) => call[0] === "fillStyle" && call[1] === "#ff0000"),
  )
})

test("the marker is skipped until the map and coordinate exist", () => {
  const ctx = effectsContext()
  drawRouteMarker(ctx, {
    map: null,
    coordinate: null,
    width: 200,
    height: 400,
  })

  assert.deepEqual(ctx.calls, [])
})

test("HUD distance and day counters keep their source formatting", () => {
  assert.deepEqual(splitDistance(850), { value: "850", unit: "m" })
  assert.deepEqual(splitDistance(12_345), { value: "12.3", unit: "km" })
  assert.deepEqual(splitDistance(Number.NaN, "mi"), { value: "0", unit: "mi" })
  const start = new Date(2026, 5, 14, 8).getTime()
  const end = new Date(2026, 5, 16, 18).getTime()
  assert.equal(dayTotal(start, end), 2)
  assert.equal(dayNumber(start, start), 1)
  assert.equal(formatDateRange(start, end), "14 — 16 JUN 2026")
})

const deferred = () => {
  let resolve
  const promise = new Promise((r) => {
    resolve = r
  })
  return { promise, resolve }
}

function fontEnvironment() {
  const loads = []
  const added = []
  class FakeFace {
    constructor(family, source, descriptors) {
      this.family = family
      this.source = source
      this.weight = descriptors.weight
      this.loaded = deferred()
      loads.push(this)
    }
    load() {
      return this.loaded.promise.then(() => this)
    }
  }
  const timers = []
  return {
    loads,
    added,
    timers,
    env: {
      FontFace: FakeFace,
      fonts: { add: (face) => added.push(face) },
      timers: {
        setTimeout: (callback, ms) => {
          const timer = { callback, ms, cleared: false }
          timers.push(timer)
          return timer
        },
        clearTimeout: (timer) => {
          if (timer) timer.cleared = true
        },
      },
    },
  }
}

const URLS = {
  "jetbrains-mono-400": "/fonts/a.woff2",
  "jetbrains-mono-700": "/fonts/b.woff2",
  "inter-400": "/fonts/c.woff2",
  "inter-700": "/fonts/d.woff2",
}

test("font completion after close cannot create a preview", async () => {
  const { loads, env } = fontEnvironment()
  const controller = new AbortController()
  let previews = 0
  const opening = (async () => {
    await ensureHudFonts(
      { ...URLS, close: "1" },
      {
        ...env,
        signal: controller.signal,
      },
    )
    previews += 1
  })()
  controller.abort()
  for (const face of loads) face.loaded.resolve()
  await assert.rejects(opening, { name: "AbortError" })
  assert.equal(previews, 0)
})

test("HUD fonts resolve to the design families and clear their timeout", async () => {
  const { loads, added, timers, env } = fontEnvironment()
  const loading = ensureHudFonts({ ...URLS, ok: "1" }, env)
  assert.equal(loads.length, 4)
  for (const face of loads) face.loaded.resolve()
  assert.deepEqual(await loading, {
    mono: HUD_MONO_FAMILY,
    sans: HUD_SANS_FAMILY,
  })
  assert.equal(added.length, 4)
  assert.equal(timers.length, 1)
  assert.equal(timers[0].cleared, true)
  assert.equal(await ensureHudFonts({ ...URLS, ok: "1" }, env), await loading)
  assert.equal(loads.length, 4)
})

test("a slow HUD font degrades to the fallback stack", async () => {
  const { timers, env } = fontEnvironment()
  const loading = ensureHudFonts({ ...URLS, slow: "1" }, env)
  timers[0].callback()
  assert.deepEqual(await loading, { mono: "monospace", sans: "sans-serif" })
  assert.deepEqual(await ensureHudFonts(null, env), {
    mono: "monospace",
    sans: "sans-serif",
  })
})
