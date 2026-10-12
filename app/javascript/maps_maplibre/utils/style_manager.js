import { translate } from "i18n"
/**
 * Style Manager for MapLibre GL styles
 * Loads and configures local map styles with dynamic tile source
 */

import {
  composeRasterFallback,
  composeVectorFallback,
} from "maps_maplibre/utils/basemap_fallback"
import { classifyBasemapUrl } from "maps_maplibre/utils/basemap_url"
import { resolveTheme } from "poster_studio/data/theme_loader"
import { buildBasemapStyle } from "poster_studio/render/style_builder"

const TILE_SOURCE_URL = "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt"

const BASEMAP_ATTRIBUTION =
  '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'

// Cache for loaded styles
const styleCache = {}

/**
 * Available map styles
 */
export const MAP_STYLES = {
  dark: "dark",
  light: "light",
  white: "white",
  black: "black",
  grayscale: "grayscale",
}

/**
 * Load a style JSON file via fetch
 * @param {string} styleName - Name of the style
 * @returns {Promise<Object>} Style object
 */
async function loadStyleFile(styleName) {
  // Check cache first
  if (styleCache[styleName]) {
    return styleCache[styleName]
  }

  // Fetch the style file from the public assets
  const response = await fetch(`/maps_maplibre/styles/${styleName}.json`)
  if (!response.ok) {
    throw new Error(`Failed to load style: ${styleName} (${response.status})`)
  }

  const style = await response.json()
  styleCache[styleName] = style
  return style
}

/**
 * Build a raster basemap style from an XYZ tile URL.
 * Reuses the light style's glyphs/sprite so re-added app label layers render.
 * @param {string} url - Raster XYZ tile URL
 * @returns {Promise<Object>} MapLibre style object
 */
async function buildRasterStyle(url) {
  const base = await loadStyleFile("light")
  return {
    version: 8,
    glyphs: base.glyphs,
    sprite: base.sprite,
    sources: {
      protomaps: {
        type: "raster",
        tiles: [url],
        tileSize: 256,
        attribution: "",
      },
    },
    layers: [
      {
        id: "background",
        type: "background",
        paint: { "background-color": "#e0e0e0" },
      },
      { id: "basemap-raster", type: "raster", source: "protomaps" },
    ],
  }
}

/**
 * Map from category keys to the style layer IDs they control.
 * Shared with map_v2_preview_controller.js — keep in sync.
 */
export const TILE_LAYER_CATEGORIES = {
  roads: [
    "roads_runway",
    "roads_taxiway",
    "roads_tunnels_other_casing",
    "roads_tunnels_minor_casing",
    "roads_tunnels_link_casing",
    "roads_tunnels_major_casing",
    "roads_tunnels_highway_casing",
    "roads_tunnels_other",
    "roads_tunnels_minor",
    "roads_tunnels_link",
    "roads_tunnels_major",
    "roads_tunnels_highway",
    "roads_pier",
    "roads_minor_service_casing",
    "roads_minor_casing",
    "roads_link_casing",
    "roads_major_casing_late",
    "roads_highway_casing_late",
    "roads_other",
    "roads_link",
    "roads_minor_service",
    "roads_minor",
    "roads_major_casing_early",
    "roads_major",
    "roads_highway_casing_early",
    "roads_highway",
    "roads_bridges_other_casing",
    "roads_bridges_link_casing",
    "roads_bridges_minor_casing",
    "roads_bridges_major_casing",
    "roads_bridges_other",
    "roads_bridges_minor",
    "roads_bridges_link",
    "roads_bridges_major",
    "roads_bridges_highway_casing",
    "roads_bridges_highway",
    "roads_oneway",
  ],
  road_labels: ["roads_labels_minor", "roads_labels_major", "roads_shields"],
  rail: ["roads_rail"],
  buildings: ["buildings"],
  address_labels: ["address_label"],
  pois: ["pois"],
  place_labels: [
    "places_subplace",
    "places_region",
    "places_locality",
    "places_country",
  ],
  water_labels: [
    "water_waterway_label",
    "water_label_ocean",
    "water_label_lakes",
  ],
  water: ["water", "water_stream", "water_river"],
  landuse: [
    "landuse_park",
    "landuse_urban_green",
    "landuse_hospital",
    "landuse_industrial",
    "landuse_school",
    "landuse_beach",
    "landuse_zoo",
    "landuse_aerodrome",
    "landuse_runway",
    "landuse_pedestrian",
    "landuse_pier",
  ],
  boundaries: ["boundaries_country", "boundaries"],
}

/**
 * POI kind groups — controls which POI kinds appear on the map.
 * Keys are group identifiers stored in user settings.
 * Values contain the label, description, and array of Protomaps `kind` strings.
 */
export const POI_GROUPS = {
  food_drink: {
    label: translate("messages.food_drink"),
    kinds: [
      "restaurant",
      "fast_food",
      "cafe",
      "bar",
      "bakery",
      "butcher",
      "greengrocer",
      "grocery",
    ],
  },
  shopping: {
    label: translate("messages.shopping"),
    kinds: [
      "supermarket",
      "convenience",
      "clothes",
      "fashion",
      "beauty",
      "hairdresser",
      "books",
      "electronics",
      "florist",
      "gift",
      "jewelry",
      "mobile_phone",
      "optician",
      "stationery",
      "bookmaker",
      "garden_centre",
    ],
  },
  transport: {
    label: translate("messages.transport"),
    kinds: [
      "aerodrome",
      "station",
      "bus_stop",
      "ferry_terminal",
      "taxi",
      "fuel",
      "charging_station",
      "parking",
      "car_rental",
      "car_wash",
      "car_repair",
    ],
  },
  cycling: {
    label: translate("messages.cycling"),
    kinds: ["bicycle_parking", "bicycle_rental", "bicycle_repair_station"],
  },
  nature_leisure: {
    label: translate("messages.nature_leisure"),
    kinds: [
      "park",
      "forest",
      "garden",
      "beach",
      "peak",
      "national_park",
      "nature_reserve",
      "zoo",
      "animal",
      "marina",
      "playground",
      "dog_park",
      "swimming_area",
      "golf_course",
      "stadium",
      "pitch",
    ],
  },
  tourism: {
    label: translate("messages.tourism_culture"),
    kinds: [
      "attraction",
      "museum",
      "theatre",
      "artwork",
      "viewpoint",
      "information",
      "camp_site",
      "picnic_site",
      "hotel",
      "hostel",
      "guest_house",
      "memorial",
    ],
  },
  services: {
    label: translate("messages.services_civic"),
    kinds: [
      "post_office",
      "post_box",
      "townhall",
      "library",
      "school",
      "university",
      "college",
      "hospital",
      "clinic",
      "doctors",
      "dentist",
      "police",
      "fire_station",
      "place_of_worship",
      "bank",
      "atm",
      "bureau_de_change",
    ],
  },
  urban_amenities: {
    label: translate("messages.urban_amenities"),
    kinds: [
      "bench",
      "toilets",
      "drinking_water",
      "fountain",
      "shelter",
      "shower",
      "telephone",
      "waste_basket",
      "waste_disposal",
      "recycling",
      "bbq",
      "picnic_table",
    ],
  },
}

/**
 * Build the full list of POI kinds for all enabled groups.
 * @param {string[]} disabledGroups - Group keys to exclude
 * @returns {string[]} Array of kind strings to include in the filter
 */
function enabledPoiKinds(disabledGroups) {
  const disabled = new Set(disabledGroups || [])
  const kinds = []
  for (const [key, group] of Object.entries(POI_GROUPS)) {
    if (!disabled.has(key)) {
      kinds.push(...group.kinds)
    }
  }
  return kinds
}

/**
 * Rewrite the `pois` layer filter to include only the given kinds.
 * Preserves the zoom-based part of the filter.
 * @param {Object} style - Cloned MapLibre style object (mutated in place)
 * @param {string[]} kinds - POI kind strings to include
 */
function applyPoiFilter(style, kinds) {
  for (const layer of style.layers) {
    if (layer.id === "pois") {
      // Build new filter: ["all", kind-filter, zoom-filter]
      // zoom-filter is the second element of the original "all" filter
      const zoomFilter = layer.filter?.[2] || [">=", ["zoom"], 0]
      layer.filter = [
        "all",
        ["in", ["get", "kind"], ["literal", kinds]],
        zoomFilter,
      ]
      break
    }
  }
}

/**
 * Collect all layer IDs that should be hidden for the given categories.
 * @param {string[]} hiddenCategories - Category keys to hide
 * @returns {Set<string>} Set of layer IDs to hide
 */
function hiddenLayerIds(hiddenCategories) {
  const ids = new Set()
  for (const cat of hiddenCategories) {
    const layers = TILE_LAYER_CATEGORIES[cat]
    if (layers) {
      for (const id of layers) ids.add(id)
    }
  }
  return ids
}

/**
 * Get a map style with configured tile source
 * @param {string} styleName - Name of the style (dark, light, white, black, grayscale)
 * @param {Object} options
 * @param {string[]} [options.hiddenTileCategories] - Category keys whose layers should be hidden
 * @param {string[]} [options.disabledPoiGroups] - POI group keys to exclude from the POI filter
 * @returns {Promise<Object>} MapLibre style object
 */
export async function getMapStyle(styleName = "light", options = {}) {
  try {
    const customUrl = options.vectorTilesUrl
    const basemapType = customUrl ? classifyBasemapUrl(customUrl) : null

    // A full MapLibre style URL replaces the whole document. Hand it to
    // setStyle/new Map, which fetch it; app layers are re-added on style.load.
    if (basemapType === "style") return customUrl

    // With the fallback on, the default basemap stays as the lower stack and
    // the user's tiles are drawn over it, so a tileset covering one country
    // no longer leaves the rest of the world blank.
    const fallback = Boolean(options.tilesFallback) && basemapType !== null

    // Raster XYZ tiles need their own source and layer — the vendored vector
    // layers cannot draw against a raster source.
    if (basemapType === "raster" && !fallback) {
      return await buildRasterStyle(customUrl)
    }

    const tilesUrl = fallback ? TILE_SOURCE_URL : customUrl || TILE_SOURCE_URL

    const composeFallback = (style) => {
      if (!fallback) return style

      return basemapType === "raster"
        ? composeRasterFallback(style, customUrl)
        : composeVectorFallback(style, customUrl)
    }

    // Custom themes are built client-side from the user's stored color
    // tokens (poster-minimal basemap) — no vendored JSON to fetch. Base-map
    // categories map onto the minimal layer set; label/POI options have no
    // counterpart there and are ignored.
    if (styleName === "custom") {
      const tokens = options.customTheme?.tokens
      if (!tokens) throw new Error("Custom map style has no theme tokens")
      return composeFallback(
        buildBasemapStyle({
          theme: resolveTheme(tokens),
          tileUrl: tilesUrl,
          extras: true,
          hiddenCategories: options.hiddenTileCategories || [],
        }),
      )
    }

    // Load the style file
    const style = await loadStyleFile(styleName)

    // Clone the style to avoid mutating the cached object
    const clonedStyle = JSON.parse(JSON.stringify(style))

    // Update the tile source URL
    if (clonedStyle.sources?.protomaps) {
      clonedStyle.sources.protomaps = {
        type: "vector",
        tiles: [tilesUrl],
        minzoom: 0,
        maxzoom: 15,
        attribution:
          clonedStyle.sources.protomaps.attribution || BASEMAP_ATTRIBUTION,
      }
    }

    // Apply hidden tile categories by setting visibility to none in the style JSON
    const hidden = options.hiddenTileCategories
    if (hidden?.length > 0) {
      const idsToHide = hiddenLayerIds(hidden)
      for (const layer of clonedStyle.layers) {
        if (idsToHide.has(layer.id)) {
          layer.layout = layer.layout || {}
          layer.layout.visibility = "none"
        }
      }
    }

    // Apply POI group filter — rewrite the pois layer to show only enabled groups
    const disabledPoi = options.disabledPoiGroups
    if (disabledPoi?.length > 0) {
      const kinds = enabledPoiKinds(disabledPoi)
      applyPoiFilter(clonedStyle, kinds)
    }

    return composeFallback(clonedStyle)
  } catch (error) {
    console.error(`Error loading style '${styleName}':`, error)
    // Fall back to light style if the requested style fails
    if (styleName !== "light") {
      console.warn(`Falling back to 'light' style`)
      return getMapStyle("light", options)
    }
    throw error
  }
}

/**
 * Get list of available style names
 * @returns {string[]} Array of style names
 */
export function getAvailableStyles() {
  return Object.keys(MAP_STYLES)
}

/**
 * Get style display name
 * @param {string} styleName - Style identifier
 * @returns {string} Human-readable style name
 */
export function getStyleDisplayName(styleName) {
  const displayNames = {
    dark: translate("map_styles.dark"),
    light: translate("map_styles.light"),
    white: translate("map_styles.white"),
    black: translate("map_styles.black"),
    grayscale: translate("map_styles.grayscale"),
  }
  return (
    displayNames[styleName] ||
    styleName.charAt(0).toUpperCase() + styleName.slice(1)
  )
}

/**
 * Preload all styles into cache for faster switching
 * @returns {Promise<void>}
 */
export async function preloadAllStyles() {
  const styleNames = getAvailableStyles()
  await Promise.all(styleNames.map((name) => loadStyleFile(name)))
  console.log("All map styles preloaded")
}
