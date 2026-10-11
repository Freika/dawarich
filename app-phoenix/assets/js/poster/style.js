import { extendTokens, resolveTheme } from "./data/theme_loader.js"
import { buildPosterStyle } from "./render/style_builder.js"

export const RESTYLE_DEBOUNCE_MS = 150

export function seedTokens(raw) {
  return { ...extendTokens(raw), ...raw }
}

export function posterStyle(state, tokens) {
  return buildPosterStyle({
    theme: resolveTheme(tokens),
    trackGeojson: state.data?.geojson,
    extras: true,
    hiddenCategories: [...state.hidden],
    trackOpacity: state.opacity / 100,
    trackWidth: state.width / 100,
  })
}

export function createRestyle({
  timers = globalThis,
  apply,
  delay = RESTYLE_DEBOUNCE_MS,
}) {
  let timer = null
  return {
    schedule() {
      timers.clearTimeout(timer)
      timer = timers.setTimeout(() => {
        timer = null
        apply()
      }, delay)
    },
    cancel() {
      timers.clearTimeout(timer)
      timer = null
    },
  }
}
