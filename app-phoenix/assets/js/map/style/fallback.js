export const CUSTOM_SOURCE_ID = "protomaps_custom"

const BASE_SOURCE_ID = "protomaps"
const CUSTOM_LAYER_SUFFIX = "__custom"
const RASTER_LAYER_ID = "basemap-raster"

export function composeVectorFallback(style, customTilesUrl) {
  const base = style.sources[BASE_SOURCE_ID]
  const customLayers = style.layers
    .filter((layer) => layer.source === BASE_SOURCE_ID)
    .map((layer) => ({
      ...layer,
      id: `${layer.id}${CUSTOM_LAYER_SUFFIX}`,
      source: CUSTOM_SOURCE_ID,
    }))

  return {
    ...style,
    sources: {
      ...style.sources,
      [CUSTOM_SOURCE_ID]: {
        type: "vector",
        tiles: [customTilesUrl],
        minzoom: base?.minzoom ?? 0,
        maxzoom: base?.maxzoom ?? 15,
        attribution: "",
      },
    },
    layers: [...style.layers, ...customLayers],
  }
}

export function composeRasterFallback(style, customTilesUrl) {
  return {
    ...style,
    sources: {
      ...style.sources,
      [CUSTOM_SOURCE_ID]: {
        type: "raster",
        tiles: [customTilesUrl],
        tileSize: 256,
        attribution: "",
      },
    },
    layers: [
      ...style.layers,
      { id: RASTER_LAYER_ID, type: "raster", source: CUSTOM_SOURCE_ID },
    ],
  }
}
