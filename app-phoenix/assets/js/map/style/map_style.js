import { buildBasemapStyle, resolveTheme } from "./dependencies.js"
import { TILE_LAYER_CATEGORIES, enabledPoiKinds } from "./layer_categories.js"

export function applyMapStyle(style, config) {
  if (config.styleName === "custom") return buildBasemapStyle({theme: resolveTheme(config.customTheme?.tokens ?? {}), tileUrl: config.tilesUrl, extras: true, hiddenCategories: config.hiddenTileCategories ?? []})
  const result = structuredClone(style)
  const hidden = new Set((config.hiddenTileCategories ?? []).flatMap(key => TILE_LAYER_CATEGORIES[key] ?? []))
  for (const layer of result.layers ?? []) {
    if (hidden.has(layer.id)) layer.layout = {...layer.layout, visibility: "none"}
    if (layer.id === "pois" && config.disabledPoiGroups?.length) layer.filter = ["all", ["in", ["get", "kind"], ["literal", enabledPoiKinds(config.disabledPoiGroups)]], layer.filter?.[2] ?? [">=", ["zoom"], 0]]
  }
  if (config.tilesUrl && result.sources?.protomaps) result.sources.protomaps = {...result.sources.protomaps, tiles: [config.tilesUrl]}
  return result
}
