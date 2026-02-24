/**
 * Style Manager for MapLibre GL styles
 * Loads and configures local map styles with dynamic tile source
 */

const TILE_SOURCE_URL = "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt"

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
 * Get a map style with configured tile source
 * @param {string} styleName - Name of the style (dark, light, white, black, grayscale)
 * @returns {Promise<Object>} MapLibre style object
 */
export async function getMapStyle(styleName = "light") {
  try {
    // Load the style file
    const style = await loadStyleFile(styleName)

    // Clone the style to avoid mutating the cached object
    const clonedStyle = JSON.parse(JSON.stringify(style))

    // Update the tile source URL
    if (clonedStyle.sources?.protomaps) {
      clonedStyle.sources.protomaps = {
        type: "vector",
        tiles: [TILE_SOURCE_URL],
        minzoom: 0,
        maxzoom: 14,
        attribution:
          clonedStyle.sources.protomaps.attribution ||
          '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>',
      }
    }

    return clonedStyle
  } catch (error) {
    console.error(`Error loading style '${styleName}':`, error)
    // Fall back to light style if the requested style fails
    if (styleName !== "light") {
      console.warn(`Falling back to 'light' style`)
      return getMapStyle("light")
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
    dark: "Dark",
    light: "Light",
    white: "White",
    black: "Black",
    grayscale: "Grayscale",
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
