/**
 * Compose a custom basemap on top of the default one.
 *
 * A tileset that covers a single country leaves the rest of the world blank.
 * Drawing it over the default basemap fills those gaps: MapLibre paints
 * nothing where the custom source has no tile, so the lower stack shows
 * through, and the custom stack's opaque `earth` fill hides the lower stack
 * wherever the custom tiles do have data.
 */

export const CUSTOM_SOURCE_ID = "protomaps_custom"

const BASE_SOURCE_ID = "protomaps"
const CUSTOM_LAYER_SUFFIX = "__custom"
const RASTER_LAYER_ID = "basemap-raster"

/**
 * Duplicate a vector style's layer stack against the user's tile URL.
 * @param {Object} style - Processed style on the default tile source
 * @param {string} customTilesUrl - Custom vector XYZ tile URL
 * @returns {Object} Style with both sources and both layer stacks
 */
export function composeVectorFallback(style, customTilesUrl) {
  const base = style.sources[BASE_SOURCE_ID]

  // The background layer paints unconditionally, so a copy of it in the upper
  // stack would hide the fallback everywhere and defeat the whole feature.
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

/**
 * Draw a raster tileset over the default vector basemap.
 * @param {Object} style - Processed style on the default tile source
 * @param {string} customTilesUrl - Custom raster XYZ tile URL
 * @returns {Object} Style with the raster layer on top
 */
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
