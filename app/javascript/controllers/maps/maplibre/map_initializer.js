import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

/**
 * Handles map initialization for Maps V2
 */
export class MapInitializer {
  /**
   * Initialize MapLibre map instance
   * @param {HTMLElement} container - The container element for the map
   * @param {Object} settings - Map settings (style, center, zoom)
   * @returns {Promise<maplibregl.Map>} The initialized map instance
   */
  static async initialize(container, settings = {}) {
    const {
      mapStyle = "streets",
      center = [0, 0],
      zoom = 2,
      showControls = true,
      globeProjection = false,
      hiddenTileCategories = [],
      disabledPoiGroups = [],
    } = settings

    const style = await getMapStyle(mapStyle, {
      hiddenTileCategories,
      disabledPoiGroups,
    })

    const mapOptions = {
      container,
      style,
      center,
      zoom,
      attributionControl: false,
    }

    const map = new maplibregl.Map(mapOptions)

    // Set globe projection after map loads
    if (globeProjection === true || globeProjection === "true") {
      map.on("load", () => {
        map.setProjection({ type: "globe" })

        // Add atmosphere effect
        map.setSky({
          "atmosphere-blend": [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            1,
            5,
            1,
            7,
            0,
          ],
        })
      })
    }

    // The bottom-right corner uses `flex-direction: column-reverse` (MapLibre
    // default), so the FIRST control added ends up at the bottom of the
    // visual stack. Add attribution first so the zoom buttons sit ABOVE it.
    map.addControl(
      new maplibregl.AttributionControl({ compact: true }),
      "bottom-right",
    )

    if (showControls) {
      // Bottom-right keeps zoom out of the way of the right-edge button
      // cluster (timeline / layers / search / replay / settings) which lives
      // along the top of the map.
      map.addControl(new maplibregl.NavigationControl(), "bottom-right")
    }

    return map
  }

  /**
   * Fit map to bounds of GeoJSON features
   * @param {maplibregl.Map} map - The map instance
   * @param {Object} geojson - GeoJSON FeatureCollection
   * @param {Object} options - Fit bounds options
   */
  static fitToBounds(map, geojson, options = {}) {
    const { padding = 50, maxZoom = 15 } = options

    if (!geojson?.features?.length) {
      console.warn("[MapInitializer] No features to fit bounds to")
      return
    }

    const coordinates = geojson.features.map((f) => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    map.fitBounds(bounds, {
      padding,
      maxZoom,
    })
  }
}
