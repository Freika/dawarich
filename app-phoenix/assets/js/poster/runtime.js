import { createLifecycle } from "../map/runtime/lifecycle.js"
import { ensurePosterFont, POSTER_FONTS } from "./data/fonts.js"
import { loadThemeTokens } from "./data/theme_loader.js"
import { trimOutlierCoords } from "./dependencies.js"
import { createPosterLifecycle } from "./lifecycle.js"
import { createPosterSource } from "./source.js"

export const interpolate = (text, values = {}) =>
  (text ?? "").replace(/%\{(\w+)\}/g, (match, name) => values[name] ?? match)

export function mountPosterStudio({
  root,
  source,
  fallbackBounds,
  loadLibrary = () => import("/maplibre/6.4.1/maplibre-gl.mjs"),
  window: win = globalThis.window,
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
      Promise.allSettled(
        POSTER_FONTS.map((font) =>
          ensurePosterFont(font.key, config.fonts ?? {}),
        ),
      ),
    trim: trimOutlierCoords,
    window: win,
    onChange: (state) => markTheme(state.themeKey),
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

  on(dialog, "close", () => studio.close())
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
