import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// hud_overlay reaches its dependencies through importmap bare specifiers,
// which Node cannot resolve — concatenate the sources with the imports
// stripped, the same approach geojson_transformers_test.mjs uses.
const read = (name) =>
  readFile(
    new URL(`../../app/javascript/video_studio/${name}.js`, import.meta.url),
    "utf8",
  )

const sources = await Promise.all(
  ["geo", "color_util", "hud_format", "route_clock", "hud_overlay"].map(read),
)
const bundle = sources
  .join("\n")
  .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  .replace(/^export /gm, "")
  .concat("\nexport { drawHud }\n")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(bundle).toString("base64")}`
const { drawHud } = await import(moduleUrl)
const MIN_HUD_SCALE = 80
const MAX_HUD_SCALE = 140

// Records everything painted, so a case can assert on what the HUD drew
// without a real canvas.
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
    // Width proportional to the string and the current font size, so
    // layout decisions that depend on measurement are exercised.
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
  ofTotal: "VON GESAMT",
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
  assert.ok(drawn.includes("VON GESAMT"))
  assert.ok(!drawn.includes("DISTANCE"))
})

test("the summary frame draws the supplied labels", () => {
  const drawn = draw({ outroProgress: 1 })

  assert.ok(drawn.includes("PRIVATE STANDORTHISTORIE"))
  // The exact day count depends on the runner's timezone; what matters is
  // that the label callback rendered rather than a hardcoded English string.
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

// The scrim keeps white HUD text legible over the map. It has to scale with
// the map's own lightness: applying a pale map's wash to a near-black one is
// what made the darkest themes render as a black rectangle.
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

// Every HUD string has to survive being watched at phone size. The source
// design's secondary tier sat under 2% of the frame's short edge, which read
// as decoration rather than information.
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

// The overlay-size control multiplies every dimension, so the composition has
// to hold at both ends of the range rather than only at 100%.
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

// The footer packs the start date, a centred credit and the end date onto one
// line. At a large overlay size they collide, and an overlapping credit is
// worse than no credit — the summary frame carries it either way.
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
      footerTexts(scale / 100).includes("https://dawarich.app"),
      `credit missing at ${scale}%`,
    )
  }
})

test("the credit survives even past the control's ceiling", () => {
  // The row shrinks to fit rather than dropping the attribution, so a wider
  // fallback font cannot make the credit disappear.
  assert.ok(footerTexts(2).includes("https://dawarich.app"))
})

test("the footer dates are never dropped either", () => {
  assert.ok(footerTexts(2).some((t) => /JUN/.test(t)))
})

test("the footer row shrinks only when it has to", () => {
  const atMax = footerFontPx(MAX_HUD_SCALE / 100)
  const unscaled = ((1080 / 100) * (MAX_HUD_SCALE / 100) * 2.4).toFixed(3)

  assert.equal(atMax.toFixed(3), unscaled)
})

// Smallest font used on the footer line, which is where the shrink applies.
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
