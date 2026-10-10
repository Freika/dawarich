import { DEFAULT_FONT_KEY } from "./data/fonts.js"
import { DEFAULT_LAYOUT_ID } from "./data/layouts.js"

export const DEFAULT_HIDDEN = ["buildings", "rail", "boundaries"]

export function initialPosterState() {
  return {
    layoutId: DEFAULT_LAYOUT_ID,
    dpi: 300,
    format: "png",
    fontKey: DEFAULT_FONT_KEY,
    hidden: new Set(DEFAULT_HIDDEN),
    opacity: 100,
    width: 100,
    textEnabled: true,
    title: "",
    subtitle: "",
    autoSubtitle: null,
    coords: true,
    data: null,
  }
}

export function withLoadedData(state, data, label) {
  const subtitleWasAuto =
    state.subtitle === "" || state.subtitle === state.autoSubtitle
  return {
    ...state,
    data,
    title: state.title || data.defaultTitle || "",
    subtitle: subtitleWasAuto ? label : state.subtitle,
    autoSubtitle: label,
  }
}
