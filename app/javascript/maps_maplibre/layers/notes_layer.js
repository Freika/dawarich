import { BaseLayer } from "./base_layer"

const EMPTY = { type: "FeatureCollection", features: [] }

export function notesToGeoJSON(notes) {
  return {
    type: "FeatureCollection",
    features: notes
      .filter((note) => note.latitude != null && note.longitude != null)
      .map((note) => ({
        type: "Feature",
        id: note.id,
        geometry: {
          type: "Point",
          coordinates: [note.longitude, note.latitude],
        },
        properties: { id: note.id, noted_at: note.noted_at },
      })),
  }
}

/**
 * Map Notes: one dot per note the user wrote at a point on the map.
 */
export class NotesLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "notes", ...options })
  }

  // A style switch drops every source; put the layer back with what it held.
  render(data = this.data || EMPTY) {
    if (this.map.getSource(this.sourceId)) this.update(data)
    else this.add(data)
  }

  getSourceConfig() {
    return { type: "geojson", data: this.data || EMPTY }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "circle",
        source: this.sourceId,
        paint: {
          "circle-radius": 8,
          "circle-color": "#f59e0b",
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
    ]
  }
}
