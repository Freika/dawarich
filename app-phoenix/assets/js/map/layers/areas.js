import { BaseLayer } from "./base.js";
import { createPlaceLabels } from "./place_labels.js";

export class AreasLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "areas", ...options });
    this.library = options.library;
  }

  add(data, beforeId = null) {
    if (!this.labels && this.library?.Marker)
      this.labels = createPlaceLabels({
        map: this.map,
        library: this.library,
        layerId: `${this.id}-fill`,
        kind: "areas",
      });
    super.add(data, beforeId);
    this.labels?.refresh();
  }

  setVisibility(visible) {
    super.setVisibility(visible);
    this.labels?.visibility(visible);
  }

  remove() {
    this.labels?.destroy();
    this.labels = null;
    super.remove();
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    };
  }

  getLayerConfigs() {
    const layers = [
      {
        id: `${this.id}-fill`,
        type: "fill",
        source: this.sourceId,
        paint: {
          "fill-color": "#ff0000",
          "fill-opacity": 0.4,
        },
      },
      {
        id: `${this.id}-outline`,
        type: "line",
        source: this.sourceId,
        paint: {
          "line-color": "#ff0000",
          "line-width": 3,
        },
      },
      {
        id: `${this.id}-labels`,
        type: "symbol",
        source: this.sourceId,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 14,
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      },
    ];
    return this.library?.Marker ? layers.slice(0, -1) : layers;
  }

  getLayerIds() {
    return [`${this.id}-fill`, `${this.id}-outline`, `${this.id}-labels`];
  }
}
