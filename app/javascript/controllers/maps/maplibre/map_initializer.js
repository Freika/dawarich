import maplibregl from 'maplibre-gl'
import { getMapStyle } from 'maps_maplibre/utils/style_manager'

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
      mapStyle = 'streets',
      center = [0, 0],
      zoom = 2,
      showControls = true
    } = settings

    const style = await getMapStyle(mapStyle)

    const map = new maplibregl.Map({
      container,
      style,
      center,
      zoom
    })

    if (showControls) {
      map.addControl(new maplibregl.NavigationControl(), 'top-right')
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
    const {
      padding = 50,
      maxZoom = 15
    } = options

    if (!geojson?.features?.length) {
      console.warn('[MapInitializer] No features to fit bounds to')
      return
    }

    const coordinates = geojson.features.map(f => f.geometry.coordinates)

    const bounds = coordinates.reduce((bounds, coord) => {
      return bounds.extend(coord)
    }, new maplibregl.LngLatBounds(coordinates[0], coordinates[0]))

    map.fitBounds(bounds, {
      padding,
      maxZoom
    })
  }
}
