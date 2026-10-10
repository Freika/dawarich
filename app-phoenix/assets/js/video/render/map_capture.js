import { hexToRgba } from "../color_util.js"
import { renderCancelled } from "../mp4_encoder.js"

export const FRESH_SOURCE_ID = "video-fresh"
const EMPTY_FC = { type: "FeatureCollection", features: [] }
const DIM_CASING_FACTOR = 0.5

const opacityOf = (layer) =>
  typeof layer?.paint?.["line-opacity"] === "number"
    ? layer.paint["line-opacity"]
    : 1

export function styleForVideo(style, { trackSourceId, accent, dimOpacity }) {
  const prepared = JSON.parse(JSON.stringify(style))
  prepared.sources[trackSourceId].data = EMPTY_FC
  prepared.sources[FRESH_SOURCE_ID] = {
    type: "geojson",
    data: EMPTY_FC,
    lineMetrics: true,
  }

  const track = prepared.layers.find((layer) => layer.id === "poster_track")
  const casing = prepared.layers.find(
    (layer) => layer.id === "poster_track_casing",
  )
  const baseOpacity = opacityOf(track)
  if (casing)
    casing.paint["line-opacity"] = opacityOf(casing) * DIM_CASING_FACTOR
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
  return prepared
}

export function createCaptureMap({
  library,
  document,
  style,
  camera,
  cssWidth,
  cssHeight,
  pixelRatio,
}) {
  const container = document.createElement("div")
  container.style.cssText = `position:fixed;left:-99999px;top:0;width:${cssWidth}px;height:${cssHeight}px;pointer-events:none;`
  document.body.appendChild(container)
  let map
  try {
    map = new library.Map({
      container,
      style,
      ...camera,
      interactive: false,
      attributionControl: false,
      preserveDrawingBuffer: true,
      fadeDuration: 0,
      pixelRatio,
    })
  } catch (error) {
    container.remove()
    throw error
  }
  return {
    map,
    release() {
      try {
        map.remove()
      } finally {
        container.remove()
      }
    },
  }
}

export function waitForIdle(
  map,
  { signal, timers, timeoutMs, failOnError = false, repaint = false },
) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(renderCancelled())
      return
    }
    let timer = null
    const settle = (finish, value) => {
      timers.clearTimeout(timer)
      map.off("idle", onIdle)
      if (failOnError) map.off("error", onError)
      signal?.removeEventListener("abort", onAbort)
      finish(value)
    }
    const onIdle = () => settle(resolve)
    const onError = (event) =>
      settle(reject, event?.error ?? new Error("Map failed to load"))
    const onAbort = () => settle(reject, renderCancelled())
    map.on("idle", onIdle)
    if (failOnError) map.on("error", onError)
    signal?.addEventListener("abort", onAbort, { once: true })
    timer = timers.setTimeout(
      () =>
        failOnError
          ? settle(reject, new Error("Map failed to load"))
          : settle(resolve),
      timeoutMs,
    )
    if (repaint) map.triggerRepaint()
  })
}
