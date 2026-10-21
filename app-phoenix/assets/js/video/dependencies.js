import { trimOutlierCoords } from "../map/algorithms/geometry.js"
import { trackBounds as posterTrackBounds } from "../poster/preview.js"

export { loadThemeTokens, resolveTheme } from "../poster/data/theme_loader.js"
export {
  buildPosterStyle,
  TRACK_SOURCE_ID,
} from "../poster/render/style_builder.js"

export const trackBounds = (geojson) =>
  posterTrackBounds(geojson, trimOutlierCoords)
