import { createLifecycle } from "../map/runtime/lifecycle.js"
import { bindPosterControls } from "./controls.js"
import { ensurePosterFont, POSTER_FONTS } from "./data/fonts.js"
import { detectMaxRenderDimension } from "./data/paper_sizes.js"
import { loadThemeTokens } from "./data/theme_loader.js"
import { dateRangeLabel } from "./dates.js"
import { trimOutlierCoords } from "./dependencies.js"
import { createPosterExports } from "./export/operation.js"
import { bindExportControls } from "./export_controls.js"
import { createPosterLifecycle } from "./lifecycle.js"
import { createPosterSource } from "./source.js"
import { interpolate } from "./strings.js"

export function mountPosterStudio({
  root,
  source,
  fallbackBounds,
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  window: win = globalThis.window,
  exports = createPosterExports(),
}) {
  const find = (name) => root.querySelector(`[data-poster-${name}]`)
  const config = JSON.parse(root.dataset.posterConfig ?? "{}")
  const strings = config.strings ?? {}
  const owned = createLifecycle()
  const swatches = [...root.querySelectorAll("[data-poster-swatch]")]
  const dialog = find("dialog")
  const setStatus = (text) => {
    const status = find("status")
    if (status) status.textContent = text
  }
  const on = (element, type, handler) => {
    if (!element) return
    element.addEventListener(type, handler)
    owned.own(() => element.removeEventListener(type, handler))
  }
  const poster = createPosterSource(source, { fallbackBounds })
  const ensureFont = (key) => ensurePosterFont(key, config.fonts ?? {})
  let controls = null
  const studio = createPosterLifecycle({
    elements: {
      dialog,
      stage: find("stage"),
      frame: find("frame"),
      map: find("map"),
      overlay: find("overlay"),
      backdrop: find("backdrop"),
    },
    poster,
    loadLibrary,
    loadThemeTokens,
    loadFonts: () =>
      Promise.allSettled(POSTER_FONTS.map((font) => ensureFont(font.key))),
    label: (data) => dateRangeLabel(data.range, data.timeZone),
    trim: trimOutlierCoords,
    window: win,
    onChange: (state) => {
      markTheme(state.themeKey)
      controls?.refresh()
    },
    onError: (code, error) =>
      setStatus(interpolate(strings[code], { error: error?.message ?? "" })),
  })

  function markTheme(key) {
    const selected = swatches.find((swatch) => swatch.dataset.key === key)
    for (const swatch of swatches) {
      swatch.classList.toggle("ring-2", swatch === selected)
      swatch.setAttribute(
        "aria-pressed",
        swatch === selected ? "true" : "false",
      )
    }
    const label = find("theme-label")
    if (label && key) label.textContent = selected?.dataset.name || key
  }

  const maxDimensionPx = detectMaxRenderDimension()
  controls = bindPosterControls({
    root,
    studio,
    poster,
    strings,
    maxDimensionPx,
    ensureFont,
  })
  owned.own(controls)
  bindExportControls({
    find,
    on,
    studio,
    exports,
    strings,
    loadLibrary,
    maxDimensionPx,
    setStatus,
  })
  owned.own(() => exports.cancel())
  on(dialog, "close", () => {
    exports.cancel()
    studio.close()
  })
  on(find("recenter"), "click", () => studio.recenter())
  for (const swatch of swatches) {
    on(swatch, "click", () =>
      studio.setTheme(swatch.dataset.key).catch((error) => {
        if (error?.name !== "AbortError")
          setStatus(
            interpolate(strings.theme_load_failed, { error: error.message }),
          )
      }),
    )
  }

  return {
    studio,
    poster,
    open: () =>
      studio.open({ themeKey: swatches[0]?.dataset.key || "blueprint" }),
    destroy() {
      owned.destroy()
      studio.destroy()
      poster.destroy()
    },
  }
}
