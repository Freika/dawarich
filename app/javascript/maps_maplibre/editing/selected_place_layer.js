import { selectedPlaceFeatures } from "maps_maplibre/editing/place_editor_state"

export class SelectedPlaceLayer {
  constructor(map, onClick = () => {}) {
    this.map = map
    this.click = (event) => onClick(event.features[0].properties.id)
    map.on("click", "selected-place", this.click)
    this.ids = [
      "selected-place-fill",
      "selected-place-boundary",
      "selected-place",
    ]
    this.restore = () => {
      if (this.place && !this.map.getSource("selected-place"))
        this.show(this.place)
    }
    map.on("render", this.restore)
  }

  show(place) {
    this.place = place
    const data = selectedPlaceFeatures(place)
    if (!this.map.isStyleLoaded()) return
    const source = this.map.getSource("selected-place")
    if (source) {
      source.setData(data)
      return
    }
    this.map.addSource("selected-place", { type: "geojson", data })
    this.map.addLayer({
      id: this.ids[0],
      type: "fill",
      source: "selected-place",
      filter: ["==", ["get", "featureKind"], "boundary"],
      paint: { "fill-color": ["get", "color"], "fill-opacity": 0.16 },
    })
    this.map.addLayer({
      id: this.ids[1],
      type: "line",
      source: "selected-place",
      filter: ["==", ["get", "featureKind"], "boundary"],
      paint: { "line-color": ["get", "color"], "line-width": 4 },
    })
    this.map.addLayer({
      id: this.ids[2],
      type: "circle",
      source: "selected-place",
      filter: ["==", ["get", "featureKind"], "center"],
      paint: {
        "circle-radius": 13,
        "circle-color": ["get", "color"],
        "circle-stroke-color": "#ffffff",
        "circle-stroke-width": 4,
      },
    })
  }

  clear() {
    this.place = null
    for (const id of this.ids.toReversed()) {
      if (this.map.getLayer(id)) this.map.removeLayer(id)
    }
    if (this.map.getSource("selected-place"))
      this.map.removeSource("selected-place")
  }

  destroy() {
    this.map.off("click", "selected-place", this.click)
    this.map.off("render", this.restore)
    this.clear()
  }
}
