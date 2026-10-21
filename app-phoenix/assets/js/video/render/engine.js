import { followCenter } from "../camera_path.js"
import { DAWARICH_BLUE, relativeLuminance } from "../color_util.js"
import { ensureHudFonts } from "../hud_fonts.js"
import { createMp4Encoder, renderCancelled } from "../mp4_encoder.js"
import { buildRenderPlan } from "../render_plan.js"
import { buildRouteClock } from "../route_clock.js"
import { buildRouteTimeline } from "../route_timeline.js"
import { RENDER_CSS_SCALE, RENDER_FIT_PADDING } from "../state.js"
import { renderFrames } from "./frame_loop.js"
import { createCaptureMap, styleForVideo, waitForIdle } from "./map_capture.js"

export const FIRST_IDLE_TIMEOUT_MS = 60_000
const DIM_TRACK_OPACITY = 0.38
const DIM_TRACK_DARK_BOOST = 0.32

function unsupported() {
  const error = new Error(
    "This browser cannot encode video. Try a current version of Chrome, Edge, Safari, or Firefox.",
  )
  error.code = "unsupported_browser"
  return error
}

function cameraFor({ follow, timeline, followZoom, bounds }) {
  if (follow) return { center: followCenter(timeline, 0), zoom: followZoom }
  if (bounds)
    return {
      bounds,
      fitBoundsOptions: { padding: RENDER_FIT_PADDING, animate: false },
    }
  return { center: [0, 0], zoom: 1 }
}

function canvas2d(document, width, height, owned) {
  const canvas = document.createElement("canvas")
  owned.push(canvas)
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext("2d")
  if (!ctx) throw new Error("Canvas 2D context unavailable")
  return { canvas, ctx }
}

export async function renderRouteVideo(options, deps) {
  const {
    kit,
    loadLibrary,
    createEncoder = createMp4Encoder,
    ensureFonts = ensureHudFonts,
    document = globalThis.document,
    timers = globalThis,
  } = deps
  const { width, height, fps = 30, signal } = options
  const accent = options.accent ?? DAWARICH_BLUE
  const themeBg = options.themeBg ?? "#ffffff"
  if (signal?.aborted) throw renderCancelled()

  const encoder = await createEncoder({ width, height, fps, signal })
  if (!encoder) throw unsupported()

  const canvases = []
  let capture = null
  try {
    const families = await ensureFonts(options.fontUrls, { signal })
    const library = await loadLibrary()
    if (signal?.aborted) throw renderCancelled()

    const dimOpacity = Math.min(
      1,
      DIM_TRACK_OPACITY +
        (1 - relativeLuminance(themeBg)) * DIM_TRACK_DARK_BOOST,
    )
    const timeline = buildRouteTimeline(options.trackGeojson, { smooth: true })
    const bounds = kit.trackBounds(options.trackGeojson)
    const follow =
      options.cameraMode === "follow" && timeline.entries.length > 0
    const followZoom = options.followZoom ?? 13.5
    const cssWidth = Math.round(width * RENDER_CSS_SCALE)
    const cssHeight = Math.round(height * RENDER_CSS_SCALE)

    capture = createCaptureMap({
      library,
      document,
      style: styleForVideo(options.style, {
        trackSourceId: kit.TRACK_SOURCE_ID,
        accent,
        dimOpacity,
      }),
      camera: cameraFor({ follow, timeline, followZoom, bounds }),
      cssWidth,
      cssHeight,
      pixelRatio: width / cssWidth,
    })
    const main = canvas2d(document, width, height, canvases)
    const fog = canvas2d(document, width, height, canvases)

    await waitForIdle(capture.map, {
      signal,
      timers,
      timeoutMs: FIRST_IDLE_TIMEOUT_MS,
      failOnError: true,
    })
    await renderFrames({
      ...options,
      map: capture.map,
      plan: buildRenderPlan({ durationSec: options.durationSec, fps }),
      encoder,
      canvas: main.canvas,
      ctx: main.ctx,
      fogCanvas: fog.canvas,
      fogCtx: fog.ctx,
      timeline,
      clock: buildRouteClock(options.points),
      bounds,
      fitPadding: RENDER_FIT_PADDING,
      follow,
      followZoom,
      trackSourceId: kit.TRACK_SOURCE_ID,
      families,
      accent,
      themeBg,
      fps,
      timers,
    })
    if (signal?.aborted) throw renderCancelled()
    return { blob: await encoder.finalize(), width, height }
  } catch (error) {
    encoder.abort()
    throw error
  } finally {
    capture?.release()
    for (const canvas of canvases) {
      canvas.width = 0
      canvas.height = 0
    }
  }
}
