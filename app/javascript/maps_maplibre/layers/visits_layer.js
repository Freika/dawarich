import { BaseLayer } from "./base_layer"

/**
 * Visits layer showing suggested, confirmed, and declined visits.
 * Green = confirmed, Amber = suggested, Grey = declined.
 *
 * Adds a halo ring for the currently selected visit, a dashed day-route
 * polyline through the day's visits in chronological order, and support
 * for filtering by status without rebuilding the source data.
 */
export class VisitsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "visits", ...options })
    this.dayRouteSourceId = `${this.sourceId}-day-route`
    this.dayRouteLayerId = `${this.id}-day-route`
    this.haloLayerId = `${this.id}-halo`
    this.labelsLayerId = `${this.id}-labels`
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  getLayerConfigs() {
    return [
      // Dashed polyline for the currently selected day, placed below
      // everything else so the visit dots sit on top.
      {
        id: this.dayRouteLayerId,
        type: "line",
        source: this.dayRouteSourceId,
        layout: {
          "line-cap": "round",
          "line-join": "round",
        },
        paint: {
          "line-color": "#22c55e",
          "line-width": 2,
          "line-opacity": 0.5,
          "line-dasharray": [2, 2],
        },
      },

      // Halo ring for the selected visit. Hidden by default via a filter
      // that can never match a real visit id.
      {
        id: this.haloLayerId,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 20,
          "circle-color": "transparent",
          "circle-stroke-color": "#22c55e",
          "circle-stroke-width": 4,
          "circle-stroke-opacity": 0.4,
        },
        filter: ["==", ["get", "id"], -1],
      },

      // Visit circles
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 12,
          "circle-color": [
            "case",
            ["==", ["get", "status"], "confirmed"],
            "#22c55e",
            ["==", ["get", "status"], "declined"],
            "#9ca3af",
            "#eab308", // suggested (default)
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.9,
        },
      },

      // Visit labels
      {
        id: this.labelsLayerId,
        type: "symbol",
        source: this.sourceId,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 11,
          "text-offset": [0, 1.5],
          "text-anchor": "top",
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      },
    ]
  }

  getLayerIds() {
    return [this.dayRouteLayerId, this.haloLayerId, this.id, this.labelsLayerId]
  }

  /**
   * Override add() so we can also create the day-route source, which
   * is independent of the main visits source.
   */
  add(data) {
    this.data = data

    if (!this.map.getSource(this.sourceId)) {
      this.map.addSource(this.sourceId, this.getSourceConfig())
    }

    if (!this.map.getSource(this.dayRouteSourceId)) {
      this.map.addSource(this.dayRouteSourceId, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      })
    }

    const layers = this.getLayerConfigs()
    layers.forEach((layerConfig) => {
      if (!this.map.getLayer(layerConfig.id)) {
        this.map.addLayer(layerConfig)
      }
    })

    this.setVisibility(this.visible)
  }

  /**
   * Override remove() so we also clean up the day-route source.
   */
  remove() {
    this.getLayerIds().forEach((layerId) => {
      if (this.map.getLayer(layerId)) {
        this.map.removeLayer(layerId)
      }
    })

    if (this.map.getSource(this.sourceId)) {
      this.map.removeSource(this.sourceId)
    }

    if (this.map.getSource(this.dayRouteSourceId)) {
      this.map.removeSource(this.dayRouteSourceId)
    }

    this.data = null
  }

  /**
   * Update() only touches the main visits source. Keep the day-route
   * source untouched so selection/filter changes don't invalidate it.
   */
  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(data)
    }
  }

  /**
   * Highlight a visit by setting the halo filter. Pass null to clear.
   * Uses `["get", "id"]` because properties.id is the visit id (see
   * data_loader.js visitsToGeoJSON).
   */
  setSelectedVisit(visitId) {
    if (!this.map.getLayer(this.haloLayerId)) return
    const id = visitId == null ? -1 : Number(visitId)
    this.map.setFilter(this.haloLayerId, ["==", ["get", "id"], id])
  }

  /**
   * Filter the visible visits by status. Does not touch the halo layer
   * so a selected visit stays highlighted regardless of filter state.
   */
  setStatusFilter({
    confirmed = true,
    suggested = true,
    declined = true,
  } = {}) {
    if (!this.map.getLayer(this.id)) return

    const allowed = []
    if (confirmed) allowed.push("confirmed")
    if (suggested) allowed.push("suggested")
    if (declined) allowed.push("declined")

    const filter =
      allowed.length === 0
        ? ["==", ["get", "status"], "__none__"]
        : ["match", ["get", "status"], allowed, true, false]

    this.map.setFilter(this.id, filter)
    if (this.map.getLayer(this.labelsLayerId)) {
      this.map.setFilter(this.labelsLayerId, filter)
    }
  }

  /**
   * Update the day-route polyline. `visitFeatures` is an array of
   * `{ lng, lat }` in chronological order. Pass `null` or an array
   * with fewer than 2 points to clear the route.
   */
  setDayRoute(visitFeatures) {
    const source = this.map.getSource(this.dayRouteSourceId)
    if (!source) return

    if (!visitFeatures || visitFeatures.length < 2) {
      source.setData({ type: "FeatureCollection", features: [] })
      return
    }

    source.setData({
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          properties: {},
          geometry: {
            type: "LineString",
            coordinates: visitFeatures.map((v) => [v.lng, v.lat]),
          },
        },
      ],
    })
  }
}
