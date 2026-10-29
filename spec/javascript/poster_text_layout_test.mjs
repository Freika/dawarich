import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

const layoutSource = await readFile(
  new URL(
    "../../app/javascript/poster_studio/render/text_layout.js",
    import.meta.url,
  ),
  "utf8",
)
const overlaySource = (
  await readFile(
    new URL(
      "../../app/javascript/poster_studio/render/overlay.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const toModule = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { layoutPosterText } = await import(toModule(layoutSource))
const { drawOverlay } = await import(
  toModule(`${layoutSource}\n${overlaySource}`)
)

// Every export shape the studio offers: paper portrait/landscape, social,
// wallpaper. The stack must hold on all of them, not just the 3:4 default.
const SHAPES = [
  [2480, 3508],
  [3508, 2480],
  [3543, 4724],
  [2550, 3300],
  [1080, 1080],
  [1080, 1350],
  [1080, 1920],
  [1500, 500],
  [1280, 720],
  [1920, 1080],
  [3440, 1440],
  [1179, 2556],
  [2064, 2752],
]

const GERMAN_STATS =
  "12.345,6 km · 28. September 2026 – 14. Oktober 2026 · Gesamtstrecke"
// Glyph advance plus the 0.2em tracking the overlay draws with.
const charMeasure = (text, size) => text.length * size * 0.8

const fullText = {
  title: "Jahresende-Zusammenfassung",
  subtitle: "28. September 2026 – 14. Oktober 2026",
  coords: "52.5200° N / 13.4050° E",
  stats: "1.234 km · 28. Sep. 2026 – 14. Okt. 2026",
}

test("without stats the default poster stack is unchanged", () => {
  const base = { width: 2480, height: 3508, ...fullText, stats: undefined }
  const withEmpty = layoutPosterText({ ...base, stats: "" })
  const without = layoutPosterText(base)

  assert.equal(without.statsY, undefined)
  assert.deepEqual(withEmpty, without)
  assert.equal(without.titleY, 3127)
})

test("the stats line sits between the subtitle and the coordinates", () => {
  const layout = layoutPosterText({
    width: 2480,
    height: 3508,
    ...fullText,
    measure: charMeasure,
  })

  assert.ok(layout.subY < layout.statsY, "stats below subtitle")
  assert.ok(layout.statsY < layout.coordsY, "stats above coordinates")
  assert.ok(layout.statsY - layout.subY >= layout.statsSize)
  assert.ok(layout.coordsY - layout.statsY >= layout.coordsSize)
})

test("stats push the title up without overlapping or leaving the poster", () => {
  for (const [width, height] of SHAPES) {
    const without = layoutPosterText({ width, height, ...fullText, stats: "" })
    const layout = layoutPosterText({
      width,
      height,
      ...fullText,
      stats: GERMAN_STATS,
      measure: charMeasure,
    })
    const shape = `${width}x${height}`

    assert.ok(layout.titleY < without.titleY, `${shape}: title moved up`)
    assert.ok(layout.titleY - layout.titleSize > 0, `${shape}: title inside`)
    assert.ok(layout.titleY < layout.dividerY, `${shape}: title above divider`)
    assert.ok(layout.dividerY < layout.subY, `${shape}: divider above sub`)
    assert.ok(
      layout.statsY - layout.subY >= layout.statsSize,
      `${shape}: stats clear of subtitle`,
    )
    assert.ok(
      layout.coordsY - layout.statsY >= layout.coordsSize,
      `${shape}: coordinates clear of stats`,
    )
    assert.ok(layout.coordsY < height, `${shape}: coordinates inside`)
    assert.equal(layout.top, layout.titleY - layout.titleSize)
  }
})

test("a long stats line shrinks to fit the poster width", () => {
  for (const [width, height] of SHAPES) {
    const layout = layoutPosterText({
      width,
      height,
      stats: GERMAN_STATS,
      measure: charMeasure,
    })

    assert.ok(
      charMeasure(GERMAN_STATS, layout.statsSize) <= width * 0.85,
      `${width}x${height}: stats line fits`,
    )
  }
})

test("a short stats line keeps its full size", () => {
  const layout = layoutPosterText({
    width: 2480,
    height: 3508,
    stats: "27.4 km",
    measure: charMeasure,
  })

  assert.equal(layout.statsSize, Math.round(2480 * 0.02))
})

function fakeCanvas(width, height) {
  const calls = { text: [], rects: [] }
  const ctx = {
    font: "",
    letterSpacing: "0px",
    createLinearGradient: () => ({ addColorStop() {} }),
    fillRect: (x, y, w, h) => calls.rects.push({ x, y, w, h }),
    fillText: (text, x, y) =>
      calls.text.push({
        text,
        x,
        y,
        size: Number.parseInt(ctx.font.split(" ")[1], 10),
      }),
    // Glyph advance only: the overlay must add its own tracking on top.
    measureText: (text) => ({
      width: text.length * Number.parseInt(ctx.font.split(" ")[1], 10) * 0.6,
    }),
    beginPath() {},
    moveTo() {},
    lineTo() {},
    stroke() {},
    save() {},
    restore() {},
  }
  return { canvas: { width, height, getContext: () => ctx }, calls }
}

const theme = { bg: "#ffffff", text: "#111111", gradientColor: "#ffffff" }

test("the overlay draws the stats line only when it is given", () => {
  const on = fakeCanvas(1080, 1350)
  drawOverlay(on.canvas, { theme, ...fullText, attribution: "" })
  const off = fakeCanvas(1080, 1350)
  drawOverlay(off.canvas, { theme, ...fullText, stats: "", attribution: "" })

  const statsCall = on.calls.text.find((c) => c.text === fullText.stats)
  assert.ok(statsCall, "stats line drawn")
  assert.equal(
    off.calls.text.some((c) => c.text === fullText.stats),
    false,
  )
  assert.equal(on.calls.text.length, off.calls.text.length + 1)
})

test("the overlay shrinks a long stats line to the poster width", () => {
  const { canvas, calls } = fakeCanvas(1080, 1350)
  drawOverlay(canvas, { theme, stats: GERMAN_STATS, attribution: "" })

  const statsCall = calls.text.find((c) => c.text === GERMAN_STATS)
  assert.ok(charMeasure(GERMAN_STATS, statsCall.size) <= 1080 * 0.85)
})

test("the bottom fade grows to keep a stats-tall stack legible", () => {
  for (const [width, height] of SHAPES) {
    const { canvas, calls } = fakeCanvas(width, height)
    drawOverlay(canvas, { theme, ...fullText, attribution: "" })
    const fade = calls.rects.at(-1)
    const layout = layoutPosterText({
      width,
      height,
      ...fullText,
      measure: charMeasure,
    })

    assert.ok(fade.y <= layout.top, `${width}x${height}: fade covers title`)
    assert.equal(fade.y + fade.h, height)
  }
})

test("the bottom fade keeps its default size without stats", () => {
  const { canvas, calls } = fakeCanvas(1500, 500)
  drawOverlay(canvas, { theme, ...fullText, stats: "", attribution: "" })

  const fade = calls.rects.at(-1)
  assert.equal(fade.h, 500 * 0.22)
})
