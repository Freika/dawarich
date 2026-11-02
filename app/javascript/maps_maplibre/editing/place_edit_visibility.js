export class PlaceEditVisibility {
  constructor(map) {
    this.map = map
    this.filters = new Map()
    this.apply = () => {
      for (const id of [
        "places-radius-fill",
        "places-radius-outline",
        "places",
      ]) {
        if (!this.map.getLayer(id)) continue
        const current = this.map.getFilter(id)
        const previous = this.filters.get(id)
        if (
          previous &&
          JSON.stringify(current) === JSON.stringify(previous.hidden)
        )
          continue
        const hidden = [
          "all",
          current || true,
          ["!=", ["get", "id"], this.placeId],
        ]
        this.filters.set(id, { original: current, hidden })
        this.map.setFilter(id, hidden)
      }
    }
  }

  hide(placeId) {
    this.restore()
    this.placeId = placeId
    this.map.on("render", this.apply)
    this.apply()
  }

  restore() {
    this.map.off("render", this.apply)
    for (const [id, { original, hidden }] of this.filters) {
      if (
        this.map.getLayer(id) &&
        JSON.stringify(this.map.getFilter(id)) === JSON.stringify(hidden)
      )
        this.map.setFilter(id, original || null)
    }
    this.filters.clear()
  }
}
