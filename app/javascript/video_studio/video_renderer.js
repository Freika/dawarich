// Renders the route replay into an MP4, entirely in the browser: a hidden
// MapLibre map is driven frame by frame (partial track via setData, camera
// via jumpTo), each settled frame is composited with the HUD onto a canvas
// and handed to the WebCodecs encoder.
import maplibregl from "maplibre-gl"
import { TRACK_SOURCE_ID } from "poster_studio/render/style_builder"
import { trackBounds } from "poster_studio/ui/preview"
import { followCenter, lerpCamera } from "video_studio/camera_path"
import {
  DAWARICH_BLUE,
  hexToRgba,
  relativeLuminance,
} from "video_studio/color_util"
import { ensureHudFonts } from "video_studio/hud_fonts"
import { drawHud } from "video_studio/hud_overlay"
import { createMp4Encoder } from "video_studio/mp4_encoder"
import { buildRenderPlan, frameFraction } from "video_studio/render_plan"
import { buildRouteClock } from "video_studio/route_clock"
import {
  buildRouteTimeline,
  sliceAtFraction,
  sliceWindow,
} from "video_studio/route_timeline"
import { RENDER_CSS_SCALE, RENDER_FIT_PADDING } from "video_studio/studio_state"

const HEAD_SOURCE_ID = "video-head"
const FRESH_SOURCE_ID = "video-fresh"
const EMPTY_FC = { type: "FeatureCollection", features: [] }
const IDLE_TIMEOUT_MS = 400
const OUTRO_FADE_FRAMES = 12

// Recency fade: the whole drawn route stays as a dim base while the last
// stretch behind the pen renders at full brightness with a fade-in tail.
const FRESH_WINDOW_FRACTION = 0.22
const DIM_TRACK_OPACITY = 0.38
const DIM_TRACK_DARK_BOOST = 0.32
const DIM_CASING_FACTOR = 0.5

// Summary pull-out: ease the camera to a view slightly wider than the fit.
const PULL_SECONDS = 1.4
const ZOOM_OUT_DELTA = 0.8

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2
}

function headFC(head) {
  if (!head) return EMPTY_FC
  return {
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        properties: {},
        geometry: { type: "Point", coordinates: head },
      },
    ],
  }
}

function styleForVideo(style, accent, dimOpacity) {
  const prepared = JSON.parse(JSON.stringify(style))
  prepared.sources[TRACK_SOURCE_ID].data = EMPTY_FC
  prepared.sources[HEAD_SOURCE_ID] = { type: "geojson", data: EMPTY_FC }
  prepared.sources[FRESH_SOURCE_ID] = {
    type: "geojson",
    data: EMPTY_FC,
    lineMetrics: true,
  }

  const track = prepared.layers.find((layer) => layer.id === "poster_track")
  const casing = prepared.layers.find(
    (layer) => layer.id === "poster_track_casing",
  )
  const baseOpacity =
    typeof track?.paint?.["line-opacity"] === "number"
      ? track.paint["line-opacity"]
      : 1
  if (casing) {
    const casingOpacity =
      typeof casing.paint?.["line-opacity"] === "number"
        ? casing.paint["line-opacity"]
        : 1
    casing.paint["line-opacity"] = casingOpacity * DIM_CASING_FACTOR
  }
  if (track) {
    track.paint["line-opacity"] = baseOpacity * dimOpacity
    const fresh = JSON.parse(JSON.stringify(track))
    fresh.id = "video_fresh"
    fresh.source = FRESH_SOURCE_ID
    fresh.paint["line-opacity"] = baseOpacity
    fresh.paint["line-gradient"] = [
      "interpolate",
      ["linear"],
      ["line-progress"],
      0,
      hexToRgba(accent, 0),
      0.35,
      hexToRgba(accent, 0.45),
      1,
      hexToRgba(accent, 1),
    ]
    prepared.layers.push(fresh)
  }

  prepared.layers.push(
    {
      id: "video_head_ring",
      type: "circle",
      source: HEAD_SOURCE_ID,
      paint: { "circle-radius": 9, "circle-color": "#ffffff" },
    },
    {
      id: "video_head_dot",
      type: "circle",
      source: HEAD_SOURCE_ID,
      paint: { "circle-radius": 6, "circle-color": accent },
    },
  )
  return prepared
}

function nextIdle(map) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      map.off("idle", onIdle)
      resolve()
    }, IDLE_TIMEOUT_MS)
    const onIdle = () => {
      clearTimeout(timer)
      resolve()
    }
    map.once("idle", onIdle)
    map.triggerRepaint()
  })
}

function throwIfAborted(signal) {
  if (signal?.aborted) throw new Error("Render cancelled")
}

export async function renderRouteVideo({
  style,
  trackGeojson,
  points,
  stats,
  width,
  height,
  fps = 30,
  durationSec,
  cameraMode = "overview",
  followZoom = 13.5,
  accent = DAWARICH_BLUE,
  units = "km",
  themeBg = "#ffffff",
  hudScale = 1,
  fontUrls,
  labels,
  watermark = null,
  onProgress,
  signal,
}) {
  const encoder = await createMp4Encoder({ width, height, fps })
  if (!encoder) {
    throw new Error(
      "This browser cannot encode video. Try a current version of Chrome, Edge, Safari, or Firefox.",
    )
  }

  // The already-drawn part of the route sits behind the pen at a reduced
  // opacity. On a pale map 38% still reads; on a near-black one it disappears,
  // so lift it as the background darkens.
  const bgLuminance = relativeLuminance(themeBg)
  const dimOpacity = Math.min(
    1,
    DIM_TRACK_OPACITY + (1 - bgLuminance) * DIM_TRACK_DARK_BOOST,
  )

  const timeline = buildRouteTimeline(trackGeojson, { smooth: true })
  const clock = buildRouteClock(points)
  const plan = buildRenderPlan({ durationSec, fps })
  const families = await ensureHudFonts(fontUrls)
  const cssWidth = Math.round(width * RENDER_CSS_SCALE)
  const cssHeight = Math.round(height * RENDER_CSS_SCALE)

  const container = document.createElement("div")
  container.style.cssText = `position:fixed;left:-99999px;top:0;width:${cssWidth}px;height:${cssHeight}px;pointer-events:none;`
  document.body.appendChild(container)

  const bounds = trackBounds(trackGeojson)
  const follow = cameraMode === "follow" && timeline.entries.length > 0
  const map = new maplibregl.Map({
    container,
    style: styleForVideo(style, accent, dimOpacity),
    ...(follow
      ? { center: followCenter(timeline, 0), zoom: followZoom }
      : bounds
        ? {
            bounds,
            fitBoundsOptions: { padding: RENDER_FIT_PADDING, animate: false },
          }
        : { center: [0, 0], zoom: 1 }),
    interactive: false,
    attributionControl: false,
    preserveDrawingBuffer: true,
    fadeDuration: 0,
    pixelRatio: width / cssWidth,
  })

  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext("2d")

  try {
    await new Promise((resolve, reject) => {
      map.once("idle", resolve)
      map.once("error", (event) =>
        reject(event.error ?? new Error("Map failed to load")),
      )
    })

    const outroStart = plan.totalFrames - plan.outroFrames
    const pullFrames = Math.min(
      plan.outroFrames,
      Math.round(PULL_SECONDS * fps),
    )
    const fit = bounds
      ? map.cameraForBounds(bounds, { padding: RENDER_FIT_PADDING })
      : null
    const pullTo = fit
      ? {
          center: [fit.center.lng, fit.center.lat],
          zoom: fit.zoom - ZOOM_OUT_DELTA,
        }
      : null
    let pullFrom = null
    let lastFraction = -1

    for (let i = 0; i < plan.totalFrames; i += 1) {
      throwIfAborted(signal)

      const fraction = frameFraction(plan, i)
      const slice = sliceAtFraction(timeline, fraction)
      if (fraction !== lastFraction) {
        const target = fraction * timeline.totalDistance
        const freshWindow = sliceWindow(
          timeline,
          target - timeline.totalDistance * FRESH_WINDOW_FRACTION,
          target,
        )
        map
          .getSource(TRACK_SOURCE_ID)
          .setData({ type: "FeatureCollection", features: slice.features })
        map.getSource(FRESH_SOURCE_ID).setData({
          type: "FeatureCollection",
          features: freshWindow.features,
        })
        map
          .getSource(HEAD_SOURCE_ID)
          .setData(headFC(fraction < 1 ? slice.head : null))
        if (follow)
          map.jumpTo({
            center: followCenter(timeline, fraction),
            zoom: followZoom,
          })
        lastFraction = fraction
      }
      if (i >= outroStart && pullTo) {
        if (!pullFrom) {
          const center = map.getCenter()
          pullFrom = { center: [center.lng, center.lat], zoom: map.getZoom() }
        }
        const eased = easeInOutCubic(
          Math.min(1, (i - outroStart + 1) / pullFrames),
        )
        const camera = lerpCamera(pullFrom, pullTo, eased)
        map.jumpTo({ center: camera.center, zoom: camera.zoom })
      }
      await nextIdle(map)

      ctx.drawImage(map.getCanvas(), 0, 0, width, height)
      drawHud(ctx, {
        width,
        height,
        fraction,
        outroProgress:
          i >= outroStart
            ? Math.min(1, (i - outroStart + 1) / OUTRO_FADE_FRAMES)
            : 0,
        // The smoothed path is slightly shorter than the recorded track, so
        // the live counter scales the real distance rather than measuring the
        // drawn line — it always lands exactly on the summary's total.
        distanceM: fraction * (stats?.distanceM ?? timeline.totalDistance),
        stats,
        units,
        accent,
        clock,
        families,
        labels,
        watermark,
        themeBg,
        hudScale,
      })

      await encoder.addFrame(canvas, i)
      onProgress?.(i + 1, plan.totalFrames)
    }

    throwIfAborted(signal)
    return { blob: await encoder.finalize(), width, height }
  } catch (error) {
    encoder.abort()
    throw error
  } finally {
    map.remove()
    container.remove()
  }
}
