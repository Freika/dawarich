import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { Toast } from "maps_maplibre/components/toast"
import { styleDocumentFailed } from "maps_maplibre/utils/basemap_url"
import {
  applyGlobeProjection,
  globeEnabled,
} from "maps_maplibre/utils/globe_projection"
import { getMapStyle } from "maps_maplibre/utils/style_manager"
import { withTileVersion } from "maps_maplibre/utils/tile_freshness"

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
      tilesFallback = false,
    } = settings

    const style = await getMapStyle(mapStyle, {
      hiddenTileCategories,
      disabledPoiGroups,
      customTheme,
      vectorTilesUrl,
      tilesFallback,
    })

    const mapOptions = {
      container,
      style,
      center,
      zoom,
      attributionControl: false,
      transformRequest: (url) => {
        const requestUrl = new URL(url, window.location.origin)

        // The origin check is load-bearing: a custom basemap or a third-party
        // style document can point a tile source at any host, and matching on
        // the path alone would hand that host the user's api key.
        if (
          requestUrl.origin !== window.location.origin ||
          !requestUrl.pathname.startsWith("/api/v1/tiles/")
        ) {
          return { url: requestUrl.toString() }
        }

        withTileVersion(requestUrl)
        if (!apiKey) return { url: requestUrl.toString() }

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
          tilesFallback,
        })
        map.setStyle(fallbackStyle, { diff: false })
      }

      map.once("style.load", onStyleLoad)
      map.on("error", onError)
    }

    if (globeEnabled(globeProjection)) {
      map.on("load", () => applyGlobeProjection(map))
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
}
