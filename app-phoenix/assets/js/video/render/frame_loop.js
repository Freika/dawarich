import { followCenter, lerpCamera } from "../camera_path.js"
import { drawHud } from "../hud_overlay.js"
import { drawFogOverlay, drawRouteMarker } from "../map_effects.js"
import { renderCancelled } from "../mp4_encoder.js"
import { frameFraction } from "../render_plan.js"
import { sliceAtFraction, sliceWindow } from "../route_timeline.js"
import { FRESH_SOURCE_ID, waitForIdle } from "./map_capture.js"

const FRAME_IDLE_TIMEOUT_MS = 400
const OUTRO_FADE_FRAMES = 12
const FRESH_WINDOW_FRACTION = 0.22
const PULL_SECONDS = 1.4
const ZOOM_OUT_DELTA = 0.8

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2
}

function pullTarget(map, bounds, padding) {
  const fit = bounds ? map.cameraForBounds(bounds, { padding }) : null
  return fit
    ? {
        center: [fit.center.lng, fit.center.lat],
        zoom: fit.zoom - ZOOM_OUT_DELTA,
      }
    : null
}

function moveTrack(map, frame, fraction) {
  const { timeline, trackSourceId, follow, followZoom } = frame
  const slice = sliceAtFraction(timeline, fraction)
  const target = fraction * timeline.totalDistance
  const freshWindow = sliceWindow(
    timeline,
    target - timeline.totalDistance * FRESH_WINDOW_FRACTION,
    target,
  )
  map
    .getSource(trackSourceId)
    .setData({ type: "FeatureCollection", features: slice.features })
  map.getSource(FRESH_SOURCE_ID).setData({
    type: "FeatureCollection",
    features: freshWindow.features,
  })
  if (follow)
    map.jumpTo({ center: followCenter(timeline, fraction), zoom: followZoom })
  return slice
}

export async function renderFrames(frame) {
  const { map, plan, encoder, canvas, ctx, fogCanvas, fogCtx, signal } = frame
  const { width, height, fps, timers, onProgress } = frame
  const outroStart = plan.totalFrames - plan.outroFrames
  const pullFrames = Math.min(plan.outroFrames, Math.round(PULL_SECONDS * fps))
  const pullTo = pullTarget(map, frame.bounds, frame.fitPadding)
  let pullFrom = null
  let lastFraction = -1
  let slice = null

  for (let i = 0; i < plan.totalFrames; i += 1) {
    if (signal?.aborted) throw renderCancelled()
    const fraction = frameFraction(plan, i)
    if (fraction !== lastFraction) {
      slice = moveTrack(map, frame, fraction)
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
    await waitForIdle(map, {
      signal,
      timers,
      timeoutMs: FRAME_IDLE_TIMEOUT_MS,
      repaint: true,
    })

    ctx.drawImage(map.getCanvas(), 0, 0, width, height)
    if (frame.visualizationMode === "fog") {
      drawFogOverlay(fogCtx, {
        map,
        features: slice.features,
        head: slice.head,
        width,
        height,
        opacity: frame.fogOpacity,
        color: frame.fogColor,
      })
      ctx.drawImage(fogCanvas, 0, 0, width, height)
    }
    if (frame.showMarker && fraction < 1) {
      drawRouteMarker(ctx, {
        map,
        coordinate: slice.head,
        width,
        height,
        accent: frame.accent,
      })
    }
    drawHud(ctx, {
      width,
      height,
      fraction,
      outroProgress:
        i >= outroStart
          ? Math.min(1, (i - outroStart + 1) / OUTRO_FADE_FRAMES)
          : 0,
      distanceM:
        fraction * (frame.stats?.distanceM ?? frame.timeline.totalDistance),
      stats: frame.stats,
      units: frame.units,
      accent: frame.accent,
      clock: frame.clock,
      families: frame.families,
      labels: frame.labels,
      watermark: frame.watermark,
      themeBg: frame.themeBg,
      hudScale: frame.hudScale,
    })

    await encoder.addFrame(canvas, i)
    onProgress?.(i + 1, plan.totalFrames)
  }
}
