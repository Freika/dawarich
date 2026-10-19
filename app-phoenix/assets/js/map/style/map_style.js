import { resolveTheme } from "../../poster/data/theme_loader.js"
import { buildBasemapStyle } from "../../poster/render/style_builder.js"
import { enabledPoiKinds, TILE_LAYER_CATEGORIES } from "./layer_categories.js"

const attribution =
  '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'

export function applyMapStyle(style, config) {
  if (config.styleName === "custom")
    return buildBasemapStyle({
      theme: resolveTheme(config.customTheme?.tokens ?? {}),
      tileUrl: config.tilesUrl,
      extras: true,
      hiddenCategories: config.hiddenTileCategories ?? [],
    })
  const result = structuredClone(style)
  const hidden = new Set(
    (config.hiddenTileCategories ?? []).flatMap(
      (key) => TILE_LAYER_CATEGORIES[key] ?? [],
    ),
  )
  for (const layer of result.layers ?? []) {
    if (hidden.has(layer.id))
      layer.layout = { ...layer.layout, visibility: "none" }
    if (layer.id === "pois" && config.disabledPoiGroups?.length)
      layer.filter = [
        "all",
        [
          "in",
          ["get", "kind"],
          ["literal", enabledPoiKinds(config.disabledPoiGroups)],
        ],
        layer.filter?.[2] ?? [">=", ["zoom"], 0],
      ]
  }
  if (result.sources?.protomaps)
    result.sources.protomaps = {
      ...result.sources.protomaps,
      ...(config.tilesUrl && { tiles: [config.tilesUrl] }),
      attribution: result.sources.protomaps.attribution || attribution,
    }
  return result
}
