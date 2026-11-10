import * as maplibregl from "maplibre-gl"
import { trimOutlierCoords } from "maps_maplibre/utils/geometry"
import { overlayAwarePadding } from "maps_maplibre/utils/map_padding"

/**
 * Fitting the map to loaded data or to the range's history bounds.
 * Mixed into the controller; `this` is the controller.
 */
export const mapFit = {
  _fitToFirstAvailable(geojsonSources) {
    for (const geojson of geojsonSources) {
      if (geojson?.features?.length > 0) {
        return this._fitMapToBounds(geojson)
      }
    }
    return false
  },

  _fitToHistoryBounds(bounds) {
    const values = bounds
      ? [bounds.min_lng, bounds.min_lat, bounds.max_lng, bounds.max_lat].map(
          Number,
        )
      : []
    if (values.length !== 4 || values.some((value) => !Number.isFinite(value)))
      return false

    const [minLng, minLat, maxLng, maxLat] = values
    return this._fitMapToBounds({
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: { type: "Point", coordinates: [minLng, minLat] },
          properties: {},
        },
        {
          type: "Feature",
          geometry: { type: "Point", coordinates: [maxLng, maxLat] },
          properties: {},
        },
      ],
    })
  },

  /**
   * Fit map to data bounds. Handles Point, LineString, and Polygon geometries.
   * Sparse extreme outliers (stray GPS points, lone far-away arcs) are trimmed
   * first so one bad coordinate can't drag the viewport into the ocean.
   * @private
   */
  _fitMapToBounds(geojson, { animate = false, skipIfCovered = false } = {}) {
    if (!geojson?.features?.length) return false

    const coords = []

    for (const feature of geojson.features) {
      const { type, coordinates } = feature.geometry
      if (type === "Point") {
        coords.push(coordinates)
      } else if (type === "LineString") {
        coords.push(...coordinates)
      } else if (type === "Polygon" || type === "MultiLineString") {
        for (const ring of coordinates) {
          coords.push(...ring)
        }
      }
    }

    const bounds = new maplibregl.LngLatBounds()
    for (const coord of trimOutlierCoords(coords)) {
      bounds.extend(coord)
    }

    if (bounds.isEmpty()) return false
    if (skipIfCovered && this._boundsCovered(bounds)) return false

    const mapRect = this.map.getContainer()?.getBoundingClientRect()
    const toolbarRect = document
      .querySelector(".map-button-cluster")
      ?.getBoundingClientRect()

    this.map.fitBounds(bounds, {
      padding: overlayAwarePadding(mapRect, toolbarRect),
      maxZoom: 15,
      animate,
    })
    return true
  },

  /**
   * Whether the current viewport already contains the given bounds.
   * @private
   */
  _boundsCovered(bounds) {
    const view = this.map.getBounds()
    return (
      view.contains(bounds.getSouthWest()) &&
      view.contains(bounds.getNorthEast())
    )
  },

  /**
   * Show a persistent upgrade banner for Lite users when the queried date
   * range extends beyond the 12-month data window.
   * @private
   */
}
