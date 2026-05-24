import { HtmlLabelManager } from "../utils/html_label_manager"
import { BaseLayer } from "./base_layer"

export class VisitsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "visits", ...options })
    this.dayRouteSourceId = `${this.sourceId}-day-route`
    this.dayRouteLayerId = `${this.id}-day-route`
    this.haloLayerId = `${this.id}-halo`
    this.labels = new HtmlLabelManager(map, {
      className: "map-html-label map-html-label--visits",
      anchor: "top",
      offset: [0, 16],
      visible: this.visible,
    })
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
            "#eab308",
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.9,
        },
      },
    ]
  }

  getLayerIds() {
    return [this.dayRouteLayerId, this.haloLayerId, this.id]
  }

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
    this.labels.sync(data?.features || [])
  }

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

    this.labels.clear()
    this.data = null
  }

  update(data) {
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(data)
    }
    this.labels.sync(data?.features || [])
  }

  setVisibility(visible) {
    super.setVisibility(visible)
    this.labels?.setVisibility(visible)
  }

  setSelectedVisit(visitId) {
    if (!this.map.getLayer(this.haloLayerId)) return
    const id = visitId == null ? -1 : Number(visitId)
    this.map.setFilter(this.haloLayerId, ["==", ["get", "id"], id])
  }

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
    this.labels.setFilter((feature) =>
      allowed.includes(feature?.properties?.status),
    )
  }

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
