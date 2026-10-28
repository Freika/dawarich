import {
  placeBounds,
  placeCameraOptions,
} from "maps_maplibre/editing/place_editor_state"

export class PlaceCamera {
  constructor(map) {
    this.map = map
  }

  fit(place) {
    this.cancel()
    this.timer = setTimeout(() => {
      this.map.resize()
      this.map.fitBounds(
        placeBounds(place),
        placeCameraOptions(
          this.map.getContainer().getBoundingClientRect(),
          document
            .querySelector(".map-control-panel.open")
            ?.getBoundingClientRect(),
          document
            .querySelector(".map-button-cluster")
            ?.getBoundingClientRect(),
        ),
      )
    }, 360)
  }

  cancel() {
    clearTimeout(this.timer)
  }
}
