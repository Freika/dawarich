import assert from "node:assert/strict"
import test from "node:test"
import {
  formatDateTimeRange,
  selectableDateTimeRange,
  toLocalDateTimeInput,
} from "../../app-phoenix/assets/js/video/date_range.js"
import { toVideoPoints } from "../../app-phoenix/assets/js/video/points.js"
import {
  buildVideoStyle,
  defaultSettings,
  formatFor,
  MAX_FOG_OPACITY,
  MAX_HUD_SCALE,
  MAX_TRACK_WIDTH,
  MIN_FOG_OPACITY,
  MIN_HUD_SCALE,
  MIN_TRACK_WIDTH,
  normalizeSettings,
  previewFitPadding,
  provenanceOf,
  RENDER_FIT_PADDING,
  rangeRestorePlan,
  readProvenance,
  renderCssSize,
  VIDEO_FORMATS,
} from "../../app-phoenix/assets/js/video/state.js"

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
    visualization_mode: "fog",
    fog_opacity: 80,
    fog_color: "#123456",
    show_marker: false,
    show_route: false,
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
  const settings = normalizeSettings({
    duration_sec: "20",
    track_width: "250",
  })

  assert.equal(settings.duration_sec, 20)
  assert.equal(settings.track_width, 250)
})

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

test("an unknown visualization mode falls back to route replay", () => {
  assert.equal(
    normalizeSettings({ visualization_mode: "satellite" }).visualization_mode,
    "route",
  )
  assert.equal(
    normalizeSettings({ visualization_mode: "fog" }).visualization_mode,
    "fog",
  )
})

test("fog opacity is numeric and clamped to the control range", () => {
  assert.equal(normalizeSettings({ fog_opacity: "75" }).fog_opacity, 75)
  assert.equal(
    normalizeSettings({ fog_opacity: 900 }).fog_opacity,
    MAX_FOG_OPACITY,
  )
  assert.equal(
    normalizeSettings({ fog_opacity: -10 }).fog_opacity,
    MIN_FOG_OPACITY,
  )
})

test("fog color keeps valid hex and rejects malformed recipe values", () => {
  assert.equal(normalizeSettings({ fog_color: "#123abc" }).fog_color, "#123abc")
  assert.equal(
    normalizeSettings({ fog_color: "linear-gradient(red, blue)" }).fog_color,
    defaultSettings().fog_color,
  )
})

test("route and marker visibility survive stored FormData strings", () => {
  const hidden = normalizeSettings({
    show_marker: "false",
    show_route: "false",
  })
  assert.equal(hidden.show_marker, false)
  assert.equal(hidden.show_route, false)

  const defaults = normalizeSettings({})
  assert.equal(defaults.show_marker, true)
  assert.equal(defaults.show_route, true)
})

test("garbage in gives defaults out", () => {
  assert.deepEqual(normalizeSettings(null), defaultSettings())
  assert.deepEqual(normalizeSettings("noir"), defaultSettings())
})

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

test("a watermark switched off stays off through a stored recipe", () => {
  assert.equal(normalizeSettings({ watermark: false }).watermark, false)
  assert.equal(normalizeSettings({ watermark: "false" }).watermark, false)
})

test("a watermark left on stays on", () => {
  assert.equal(normalizeSettings({ watermark: "true" }).watermark, true)
  assert.equal(normalizeSettings({}).watermark, true)
})

test("track width is clamped to the range the control offers", () => {
  assert.equal(
    normalizeSettings({ track_width: 900 }).track_width,
    MAX_TRACK_WIDTH,
  )
  assert.equal(
    normalizeSettings({ track_width: 10 }).track_width,
    MIN_TRACK_WIDTH,
  )
})

test("a negative legacy track width lands on the floor, not below it", () => {
  assert.equal(
    normalizeSettings({ track_width: -2 }).track_width,
    MIN_TRACK_WIDTH,
  )
})

test("provenance records the range and which surface the video came from", () => {
  const trip = provenanceOf({
    fixed: true,
    range: { startAt: "2026-06-14", endAt: "2026-06-16" },
  })
  assert.deepEqual(trip, {
    source: "trip",
    start_at: "2026-06-14",
    end_at: "2026-06-16",
  })

  const map = provenanceOf({
    fixed: false,
    range: { startAt: "2026-06-14", endAt: "2026-06-16" },
  })
  assert.equal(map.source, "map")
})

test("provenance survives a missing or broken provider", () => {
  assert.deepEqual(provenanceOf(null), {
    source: "map",
    start_at: "",
    end_at: "",
  })
})

test("a stored recipe gives its provenance back", () => {
  assert.deepEqual(
    readProvenance({
      theme: "noir",
      source: "trip",
      start_at: "2026-06-14",
      end_at: "2026-06-16",
    }),
    { source: "trip", start_at: "2026-06-14", end_at: "2026-06-16" },
  )
})

test("a recipe with no provenance reports none", () => {
  assert.equal(readProvenance({ theme: "noir" }), null)
  assert.equal(readProvenance(null), null)
})

const MAP = { fixed: false }
const TRIP = { fixed: true }
const SHOWING = { startAt: "2026-06-01", endAt: "2026-06-02" }

test("a recipe with no provenance leaves the range alone", () => {
  assert.equal(rangeRestorePlan(null, SHOWING, MAP).action, "none")
})

test("a recipe already on screen needs no navigation", () => {
  const plan = rangeRestorePlan(
    { source: "map", start_at: SHOWING.startAt, end_at: SHOWING.endAt },
    SHOWING,
    MAP,
  )
  assert.equal(plan.action, "none")
})

test("a map recipe from another range navigates back to it", () => {
  const plan = rangeRestorePlan(
    { source: "map", start_at: "2026-05-01", end_at: "2026-05-09" },
    SHOWING,
    MAP,
  )
  assert.equal(plan.action, "navigate")
  assert.equal(plan.start_at, "2026-05-01")
  assert.equal(plan.end_at, "2026-05-09")
})

test("a trip recipe warns instead of navigating", () => {
  const plan = rangeRestorePlan(
    { source: "trip", start_at: "2026-05-01", end_at: "2026-05-09" },
    SHOWING,
    TRIP,
  )
  assert.equal(plan.action, "warn")
  assert.equal(plan.range, "2026-05-01 - 2026-05-09")
})

test("a map recipe opened inside a trip studio warns too", () => {
  const plan = rangeRestorePlan(
    { source: "map", start_at: "2026-05-01", end_at: "2026-05-09" },
    SHOWING,
    TRIP,
  )
  assert.equal(plan.action, "warn")
})

test("a navigate plan still describes its range", () => {
  const plan = rangeRestorePlan(
    { source: "map", start_at: "2026-05-01", end_at: "" },
    SHOWING,
    MAP,
  )
  assert.equal(plan.range, "2026-05-01")
})

test("reads GeoJSON features from the map's point layers", () => {
  const points = toVideoPoints([
    {
      geometry: { coordinates: [13.4, 52.5] },
      properties: { timestamp: 1_700_000_000 },
    },
  ])

  assert.equal(points.length, 1)
  assert.equal(points[0].lat, 52.5)
  assert.equal(points[0].lon, 13.4)
  assert.equal(points[0].time, "2023-11-14T22:13:20.000Z")
})

test("reads raw points in both longitude/latitude and lon/lat shapes", () => {
  const points = toVideoPoints([
    { longitude: 13.4, latitude: 52.5, timestamp: 1_700_000_000 },
    { lon: 13.41, lat: 52.51, timestamp: 1_700_000_060 },
  ])

  assert.deepEqual(
    points.map((point) => point.lon),
    [13.4, 13.41],
  )
})

test("treats a large timestamp as milliseconds, a small one as seconds", () => {
  const [seconds, millis] = toVideoPoints([
    { lon: 0, lat: 0, timestamp: 1_700_000_000 },
    { lon: 0, lat: 0, timestamp: 1_700_000_000_000 },
  ])

  assert.equal(seconds.time, millis.time)
})

test("accepts an ISO timestamp string", () => {
  const [point] = toVideoPoints([
    { lon: 0, lat: 0, timestamp: "2026-06-14T08:41:00Z" },
  ])

  assert.equal(point.time, "2026-06-14T08:41:00.000Z")
})

test("accepts the decimal strings the points API actually returns", () => {
  const [point] = toVideoPoints([
    {
      id: 1,
      latitude: "51.3402",
      longitude: "12.3712",
      timestamp: 1_781_424_000,
    },
  ])

  assert.equal(point.lat, 51.3402)
  assert.equal(point.lon, 12.3712)
})

test("keeps timeless points so the distance still counts", () => {
  const [point] = toVideoPoints([{ lon: 13.4, lat: 52.5 }])

  assert.equal(point.time, null)
  assert.equal(point.lat, 52.5)
})

test("drops points with no usable coordinates", () => {
  const points = toVideoPoints([
    { timestamp: 1_700_000_000 },
    { lon: "west", lat: 52.5 },
    null,
  ])

  assert.deepEqual(points, [])
})

test("returns an empty list for anything that is not an array", () => {
  assert.deepEqual(toVideoPoints(undefined), [])
  assert.deepEqual(toVideoPoints({ points: [] }), [])
})

test("datetime picker seed keeps the local date and minute", () => {
  assert.equal(toLocalDateTimeInput("2026-07-11T14:30:45"), "2026-07-11T14:30")
})

test("datetime picker seed uses the configured timezone", () => {
  assert.equal(
    toLocalDateTimeInput("2026-07-11T12:30:45Z", "Europe/Berlin"),
    "2026-07-11T14:30",
  )
})

test("selected range keeps both chosen times", () => {
  assert.deepEqual(
    selectableDateTimeRange("2026-07-11T14:30", "2026-07-11T18:45"),
    { start: "2026-07-11T14:30", end: "2026-07-11T18:45" },
  )
})

test("selected range carries the configured timezone offset", () => {
  assert.deepEqual(
    selectableDateTimeRange(
      "2026-07-11T14:30",
      "2026-07-11T18:45",
      "Europe/Berlin",
    ),
    {
      start: "2026-07-11T14:30+02:00",
      end: "2026-07-11T18:45+02:00",
    },
  )
})

test("selected range rejects a wall time skipped by daylight saving", () => {
  assert.equal(
    selectableDateTimeRange(
      "2026-03-29T02:30",
      "2026-03-29T04:00",
      "Europe/Berlin",
    ),
    null,
  )
})

test("selected range rejects an ambiguous wall time repeated by daylight saving", () => {
  assert.equal(
    selectableDateTimeRange(
      "2026-10-25T02:30",
      "2026-10-25T04:00",
      "Europe/Berlin",
    ),
    null,
  )
})

test("selected range rejects missing, equal, backwards, or invalid times", () => {
  assert.equal(selectableDateTimeRange("", "2026-07-11T18:45"), null)
  assert.equal(
    selectableDateTimeRange("2026-07-11T14:30", "2026-07-11T14:30"),
    null,
  )
  assert.equal(
    selectableDateTimeRange("2026-07-11T18:45", "2026-07-11T14:30"),
    null,
  )
  assert.equal(selectableDateTimeRange("not-a-date", "also-not-a-date"), null)
})

test("range label shows the start and end times", () => {
  const label = formatDateTimeRange(
    "2026-07-11T14:30",
    "2026-07-11T18:45",
    "en-GB",
  )
  assert.match(label, /14:30/)
  assert.match(label, /18:45/)
})

test("range label uses the configured timezone", () => {
  const label = formatDateTimeRange(
    "2026-07-11T12:30:00Z",
    "2026-07-11T16:45:00Z",
    "en-GB",
    "Europe/Berlin",
  )
  assert.match(label, /14:30/)
  assert.match(label, /18:45/)
})

test("range conversion uses profile timezone across DST", () => {
  assert.deepEqual(
    selectableDateTimeRange(
      "2026-03-28T10:00",
      "2026-03-30T10:00",
      "Europe/Berlin",
    ),
    { start: "2026-03-28T10:00+01:00", end: "2026-03-30T10:00+02:00" },
  )
  assert.deepEqual(
    selectableDateTimeRange(
      "2026-11-01T00:30",
      "2026-11-02T00:30",
      "America/New_York",
    ),
    { start: "2026-11-01T00:30-04:00", end: "2026-11-02T00:30-05:00" },
  )
})

test("video normalization and recipe preserve original format values", () => {
  const stored = {
    theme: "noir",
    format: "square",
    duration_sec: "12",
    camera_mode: "follow",
    follow_zoom: "11.5",
    track_color: "#00aa11",
    track_width: "180",
    visualization_mode: "fog",
    fog_opacity: "40",
    fog_color: "#102030",
    show_marker: "false",
    show_route: "true",
    units: "mi",
    hud_scale: "90",
    watermark: "false",
  }
  assert.deepEqual(normalizeSettings(stored), {
    theme: "noir",
    format: "square",
    duration_sec: 12,
    camera_mode: "follow",
    follow_zoom: 11.5,
    track_color: "#00aa11",
    track_width: 180,
    visualization_mode: "fog",
    fog_opacity: 40,
    fog_color: "#102030",
    show_marker: false,
    show_route: true,
    units: "mi",
    hud_scale: 90,
    watermark: false,
  })
  assert.deepEqual(formatFor(normalizeSettings(stored)), VIDEO_FORMATS.square)
})

test("video style is built from injected poster style services", () => {
  const calls = []
  const kit = {
    resolveTheme: (tokens) => ({ resolved: tokens.bg }),
    buildPosterStyle: (options) => {
      calls.push(options)
      return { version: 8 }
    },
  }
  const settings = { ...defaultSettings(), show_route: false, track_width: 150 }
  assert.equal(
    buildVideoStyle({ tokens: null, trackGeojson: null, settings }, kit),
    null,
  )
  const track = { type: "FeatureCollection", features: [] }
  assert.deepEqual(
    buildVideoStyle(
      { tokens: { bg: "#fff" }, trackGeojson: track, settings },
      kit,
    ),
    { version: 8 },
  )
  assert.deepEqual(calls, [
    {
      theme: { resolved: "#fff" },
      trackGeojson: track,
      trackColor: settings.track_color,
      trackOpacity: 0,
      trackWidth: 1.5,
    },
  ])
})

test("stored recipes with inherited format names fall back to finite portrait dimensions", () => {
  for (const format of [
    "__proto__",
    "constructor",
    "toString",
    "hasOwnProperty",
  ]) {
    const stored = JSON.parse(JSON.stringify({ format }))
    const settings = normalizeSettings(stored)
    assert.equal(settings.format, "portrait", format)
    assert.deepEqual(formatFor(settings), VIDEO_FORMATS.portrait)
    assert.deepEqual(formatFor(stored), VIDEO_FORMATS.portrait)
    const { width, height } = renderCssSize(stored)
    assert.ok(Number.isFinite(width) && Number.isFinite(height))
  }
})
