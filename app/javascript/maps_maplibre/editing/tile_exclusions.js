// Range changes replace MapLibre sources and discard their filters, and flight
// toggles swap the base filter. apply() re-captures the current base filter
// (unless it is still the one this instance set) and puts the focused edit
// exclusions back on top.
export class TileExclusions {
  constructor(map) {
    this.map = map
    this.active = false
  }

  apply({ trackId, pointIds }) {
    this.previousTrackFilter = this._base(
      "tracks-mvt",
      this.appliedTrackFilter,
      this.previousTrackFilter,
    )
    this.previousPointFilter = this._base(
      "points-mvt",
      this.appliedPointFilter,
      this.previousPointFilter,
    )
    this.active = true
    this.appliedTrackFilter = null
    this.appliedPointFilter = null
    if (trackId && this.map.getLayer("tracks-mvt")) {
      this.appliedTrackFilter = this._combine(this.previousTrackFilter, [
        "!=",
        ["get", "id"],
        trackId,
      ])
      this.map.setFilter("tracks-mvt", this.appliedTrackFilter)
    }
    if (this.map.getLayer("points-mvt")) {
      this.appliedPointFilter = this._combine(this.previousPointFilter, [
        "!",
        ["in", ["get", "id"], ["literal", pointIds]],
      ])
      this.map.setFilter("points-mvt", this.appliedPointFilter)
    }
  }

  restore() {
    if (!this.active) return
    this.active = false
    if (this.map.getLayer("tracks-mvt"))
      this.map.setFilter("tracks-mvt", this.previousTrackFilter)
    if (this.map.getLayer("points-mvt"))
      this.map.setFilter("points-mvt", this.previousPointFilter)
  }

  _base(layerId, applied, previous) {
    const current = this.map.getFilter?.(layerId) || null
    const stillOurs =
      this.active &&
      applied &&
      JSON.stringify(current) === JSON.stringify(applied)
    return stillOurs ? previous : current
  }

  _combine(base, exclusion) {
    return base ? ["all", base, exclusion] : exclusion
  }
}
