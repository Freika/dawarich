import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

// studio_state imports the poster style builder, which the render path needs
// but these cases do not — strip the imports and exercise the pure settings
// helpers, the same approach the other javascript specs take.
const source = await readFile(
  new URL("../../app/javascript/video_studio/studio_state.js", import.meta.url),
  "utf8",
)
const withoutImports = source
  .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  .replace(/\bDAWARICH_BLUE\b/g, '"#2563EB"')
  .replace(
    /export function buildVideoStyle[\s\S]*$/m,
    "export function buildVideoStyle() { return null }\n",
  )
const moduleUrl = `data:text/javascript;base64,${Buffer.from(withoutImports).toString("base64")}`
const {
  defaultSettings,
  formatFor,
  normalizeSettings,
  MAX_HUD_SCALE,
  MIN_HUD_SCALE,
  previewFitPadding,
  renderCssSize,
  RENDER_FIT_PADDING,
  VIDEO_FORMATS,
} = await import(moduleUrl)

test("the default settings render a portrait video", () => {
  assert.deepEqual(formatFor(defaultSettings()), VIDEO_FORMATS.portrait)
})

test("an unknown format falls back to portrait rather than breaking a render", () => {
  assert.deepEqual(formatFor({ format: "imax" }), VIDEO_FORMATS.portrait)
})

test("a stored recipe round-trips unchanged", () => {
  const settings = {
    theme: "sunset",
    format: "landscape",
    duration_sec: 22,
    camera_mode: "follow",
    follow_zoom: 12,
    track_color: "#ff0000",
    track_width: 240,
    units: "mi",
    hud_scale: 130,
    watermark: false,
  }

  assert.deepEqual(normalizeSettings(settings), settings)
})

test("a duration outside the studio's range is clamped, not rejected", () => {
  assert.equal(normalizeSettings({ duration_sec: 900 }).duration_sec, 30)
  assert.equal(normalizeSettings({ duration_sec: 1 }).duration_sec, 8)
})

test("values that arrived as strings become numbers", () => {
  const settings = normalizeSettings({ duration_sec: "20", track_width: "250" })

  assert.equal(settings.duration_sec, 20)
  assert.equal(settings.track_width, 250)
})

// Route width is stored as a percent to match the poster studio's route_width.
// Recipes saved before that alignment held a 0.5-3.0 multiplier, and reading
// one of those as a percent would render a hairline instead of the route.
test("a legacy multiplier route width is read as a multiplier, not a percent", () => {
  assert.equal(normalizeSettings({ track_width: 1.2 }).track_width, 120)
  assert.equal(normalizeSettings({ track_width: 3 }).track_width, 300)
})

test("a percent route width is left alone", () => {
  assert.equal(normalizeSettings({ track_width: 120 }).track_width, 120)
  assert.equal(normalizeSettings({ track_width: 50 }).track_width, 50)
})

test("a recipe from an older release keeps working", () => {
  const settings = normalizeSettings({ theme: "noir", camera_mode: "orbit" })

  assert.equal(settings.camera_mode, "overview")
  assert.equal(settings.format, "portrait")
  assert.equal(settings.units, "km")
})

test("the watermark stays on unless it was explicitly turned off", () => {
  assert.equal(normalizeSettings({}).watermark, true)
  assert.equal(normalizeSettings({ watermark: false }).watermark, false)
})

test("garbage in gives defaults out", () => {
  assert.deepEqual(normalizeSettings(null), defaultSettings())
  assert.deepEqual(normalizeSettings("noir"), defaultSettings())
})

// The preview and the renderer must frame the route identically. The renderer
// fits at half the export size with a fixed pixel padding, so a preview of a
// different size has to scale that padding or it shows a framing the video
// will not reproduce.
test("the render lays out at half the export size", () => {
  assert.deepEqual(renderCssSize({ format: "portrait" }), {
    width: 540,
    height: 960,
  })
  assert.deepEqual(renderCssSize({ format: "landscape" }), {
    width: 960,
    height: 540,
  })
})

test("a preview the same size as the render uses the render's padding", () => {
  const settings = { format: "portrait" }

  assert.equal(previewFitPadding(settings, 540), RENDER_FIT_PADDING)
})

test("a smaller preview gets proportionally smaller padding", () => {
  const settings = { format: "portrait" }

  assert.equal(previewFitPadding(settings, 270), RENDER_FIT_PADDING / 2)
})

test("padding follows the format, not just the pixel width", () => {
  const portrait = previewFitPadding({ format: "portrait" }, 480)
  const landscape = previewFitPadding({ format: "landscape" }, 480)

  // Landscape lays out at 960 CSS px, so the same preview width is a smaller
  // fraction of it and needs less padding.
  assert.ok(landscape < portrait)
})

test("an unmeasured preview falls back to the render padding", () => {
  assert.equal(previewFitPadding({ format: "portrait" }, 0), RENDER_FIT_PADDING)
})

test("overlay size is clamped to the range the control offers", () => {
  assert.equal(normalizeSettings({ hud_scale: 500 }).hud_scale, MAX_HUD_SCALE)
  assert.equal(normalizeSettings({ hud_scale: 5 }).hud_scale, MIN_HUD_SCALE)
})

test("a recipe with no overlay size gets the default", () => {
  assert.equal(normalizeSettings({}).hud_scale, defaultSettings().hud_scale)
})
