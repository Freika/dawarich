import { translate } from "i18n"
import maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { styleDocumentFailed } from "maps_maplibre/utils/basemap_url"
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
  static async initialize(container, settings = {}, apiKey = null) {
    const {
      mapStyle = "streets",
      center = [0, 0],
      zoom = 2,
      showControls = true,
      globeProjection = false,
      hiddenTileCategories = [],
      disabledPoiGroups = [],
      customTheme = null,
      vectorTilesUrl = null,
    } = settings

    const style = await getMapStyle(mapStyle, {
      hiddenTileCategories,
      disabledPoiGroups,
      customTheme,
      vectorTilesUrl,
    })

    const mapOptions = {
      container,
      style,
      center,
      zoom,
      attributionControl: false,
      transformRequest: (url) => {
        const requestUrl = new URL(url, window.location.origin)

        if (!requestUrl.pathname.startsWith("/api/v1/tiles/") || !apiKey) {
          return { url: requestUrl.toString() }
        }

        return {
          url: requestUrl.toString(),
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
        }
      },
    }

    const map = new maplibregl.Map(mapOptions)

    if (typeof style === "string") {
      let settled = false

      const onStyleLoad = () => {
        if (settled) return
        settled = true
        map.off("error", onError)
      }
      // Tile, sprite and glyph failures also surface as `error`. Reverting on
      // those would discard a custom style that loaded perfectly well, so only
      // a failure of the style document itself counts.
      const onError = async (event) => {
        if (settled || !styleDocumentFailed(event, style)) return
        settled = true
        map.off("style.load", onStyleLoad)
        map.off("error", onError)
        Toast.error(translate("settings.custom_style_load_failed"))
        const fallbackStyle = await getMapStyle(mapStyle, {
          hiddenTileCategories,
          disabledPoiGroups,
          customTheme,
        })
        map.setStyle(fallbackStyle, { diff: false })
      }

      map.once("style.load", onStyleLoad)
      map.on("error", onError)
    }

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

    if (showControls) {
      map.addControl(new maplibregl.NavigationControl(), "top-right")
    }

    map.addControl(
      new maplibregl.AttributionControl({ compact: true }),
      "bottom-right",
    )

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
