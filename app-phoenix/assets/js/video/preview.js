import { drawHud } from "./hud_overlay.js"
import { drawFogOverlay, drawRouteMarker } from "./map_effects.js"
import { sliceAtFraction } from "./route_timeline.js"
import { DAWARICH_URL, formatFor, previewFitPadding } from "./state.js"

const HUD_PREVIEW_FRACTION = 0.62
const STAGE_PADDING = 48

export function createVideoPreview({ elements, library, window: win }) {
  let map = null
  let view = null
  const redraw = () => drawOverlay()

  function resizeFrame() {
    const { stage, frame } = elements
    if (!stage || !frame || !view) return
    const { width, height } = formatFor(view.settings)
    const box = stage.getBoundingClientRect()
    const scale = Math.min(
      Math.max(0, box.width - STAGE_PADDING) / width,
      Math.max(0, box.height - STAGE_PADDING) / height,
    )
    frame.style.width = `${Math.round(width * scale)}px`
    frame.style.height = `${Math.round(height * scale)}px`
  }

  function fitOptions() {
    return {
      padding: previewFitPadding(
        view.settings,
        elements.frame?.getBoundingClientRect().width,
      ),
      animate: false,
    }
  }

  function clearOverlay() {
    const canvas = elements.overlay
    canvas?.getContext("2d")?.clearRect(0, 0, canvas.width, canvas.height)
  }

  function drawOverlay() {
    const canvas = elements.overlay
    if (!canvas || !view?.stats || !elements.frame) return
    const box = elements.frame.getBoundingClientRect()
    if (!box.width || !box.height) return
    const ratio = Math.min(win?.devicePixelRatio || 1, 2)
    canvas.width = Math.round(box.width * ratio)
    canvas.height = Math.round(box.height * ratio)
    const ctx = canvas.getContext("2d")
    if (!ctx) return
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    const { settings } = view
    const slice = sliceAtFraction(view.timeline, HUD_PREVIEW_FRACTION)
    const size = { width: canvas.width, height: canvas.height }
    if (settings.visualization_mode === "fog")
      drawFogOverlay(ctx, {
        map,
        features: slice.features,
        head: slice.head,
        ...size,
        opacity: settings.fog_opacity / 100,
        color: settings.fog_color,
      })
    if (settings.show_marker)
      drawRouteMarker(ctx, {
        map,
        coordinate: slice.head,
        ...size,
        accent: settings.track_color,
      })
    drawHud(ctx, {
      ...size,
      fraction: HUD_PREVIEW_FRACTION,
      outroProgress: 0,
      distanceM: (view.stats.distanceM ?? 0) * HUD_PREVIEW_FRACTION,
      stats: view.stats,
      units: settings.units,
      accent: settings.track_color,
      clock: view.clock,
      families: view.families,
      labels: view.labels,
      watermark: settings.watermark ? DAWARICH_URL : null,
      themeBg: view.themeBg,
      hudScale: settings.hud_scale / 100,
    })
  }

  function show(next) {
    view = next
    if (!view.style) return
    resizeFrame()
    const bounds = view.bounds
    if (map) {
      map.setStyle(view.style)
      map.resize()
      if (bounds) map.fitBounds(bounds, fitOptions())
      drawOverlay()
      return
    }
    map = new library.Map({
      container: elements.preview,
      style: view.style,
      ...(bounds
        ? { bounds, fitBoundsOptions: fitOptions() }
        : { center: [0, 0], zoom: 1 }),
      interactive: false,
      attributionControl: false,
    })
    map.once("idle", redraw)
  }

  return {
    show,
    drawOverlay,
    clearOverlay,
    resize() {
      resizeFrame()
      map?.resize()
      drawOverlay()
    },
    destroy() {
      if (map) {
        map.off("idle", redraw)
        map.remove()
      }
      map = null
      view = null
      clearOverlay()
    },
    get map() {
      return map
    },
  }
}
